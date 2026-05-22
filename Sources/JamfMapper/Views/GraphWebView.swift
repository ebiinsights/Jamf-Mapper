@preconcurrency import WebKit
import JamfMapperCore
import SwiftUI

@MainActor
struct GraphWebView: NSViewRepresentable {
    let graph: GraphSnapshot
    @Binding var selectedNodeKey: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedNodeKey: $selectedNodeKey)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "jamfMapper")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(Self.html, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.pendingGraph = graph
        context.coordinator.renderIfReady(in: webView)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var selectedNodeKey: Binding<String?>
        var isReady = false
        var pendingGraph: GraphSnapshot?

        init(selectedNodeKey: Binding<String?>) {
            self.selectedNodeKey = selectedNodeKey
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            renderIfReady(in: webView)
        }

        func renderIfReady(in webView: WKWebView) {
            guard isReady, let pendingGraph else { return }
            let payload = GraphWebPayload(graph: pendingGraph)
            let encoder = JSONEncoder()
            guard let data = try? encoder.encode(payload), let json = String(data: data, encoding: .utf8) else { return }
            webView.evaluateJavaScript("window.renderGraph(\(json));")
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "jamfMapper", let body = message.body as? [String: Any], let key = body["nodeKey"] as? String else {
                return
            }
            selectedNodeKey.wrappedValue = key
        }
    }

    private struct GraphWebPayload: Encodable {
        struct Node: Encodable {
            var data: NodeData
        }
        struct NodeData: Encodable {
            var id: String
            var label: String
            var type: String
            var enabled: Bool?
            var orphan: Bool
        }
        struct Edge: Encodable {
            var data: EdgeData
        }
        struct EdgeData: Encodable {
            var id: String
            var source: String
            var target: String
            var label: String
        }
        var nodes: [Node]
        var edges: [Edge]

        init(graph: GraphSnapshot) {
            let incoming = Dictionary(grouping: graph.edges, by: \.toKey)
            let outgoing = Dictionary(grouping: graph.edges, by: \.fromKey)
            nodes = graph.nodes.map { node in
                Node(data: NodeData(id: node.key, label: node.name, type: node.objectType.rawValue, enabled: node.isEnabled, orphan: incoming[node.key, default: []].isEmpty && outgoing[node.key, default: []].isEmpty))
            }
            edges = graph.edges.map { edge in
                Edge(data: EdgeData(id: edge.key, source: edge.fromKey, target: edge.toKey, label: edge.label))
            }
        }
    }

    private static let html = """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <style>
        html, body, #cy { width: 100%; height: 100%; margin: 0; overflow: hidden; font-family: -apple-system, BlinkMacSystemFont, sans-serif; }
        body { background: transparent; }
        #fallback { display: none; width: 100%; height: 100%; }
        .hint { position: fixed; left: 14px; bottom: 12px; color: #777; font-size: 12px; }
      </style>
      <script src="https://unpkg.com/cytoscape@3.29.2/dist/cytoscape.min.js"></script>
    </head>
    <body>
      <div id="cy"></div>
      <svg id="fallback"></svg>
      <div class="hint">Scroll to zoom, drag to pan, click nodes to inspect.</div>
      <script>
        let cy = null;
        const colors = {
          policy: '#3b82f6', smartGroup: '#14b8a6', staticGroup: '#0f766e',
          extensionAttribute: '#f97316', script: '#8b5cf6', package: '#64748b',
          category: '#eab308', computerConfigurationProfile: '#06b6d4',
          mobileConfigurationProfile: '#06b6d4', macApplication: '#ec4899',
          patchPolicy: '#ef4444', patchTitle: '#f43f5e', appInstaller: '#22c55e'
        };

        function renderFallback(payload) {
          const svg = document.getElementById('fallback');
          document.getElementById('cy').style.display = 'none';
          svg.style.display = 'block';
          svg.innerHTML = '';
          const width = window.innerWidth, height = window.innerHeight;
          const nodes = payload.nodes.map((n, i) => ({...n.data, x: 80 + (i % 8) * 150, y: 80 + Math.floor(i / 8) * 95}));
          const byId = Object.fromEntries(nodes.map(n => [n.id, n]));
          for (const edge of payload.edges) {
            const s = byId[edge.data.source], t = byId[edge.data.target];
            if (!s || !t) continue;
            const line = document.createElementNS('http://www.w3.org/2000/svg', 'line');
            line.setAttribute('x1', s.x); line.setAttribute('y1', s.y); line.setAttribute('x2', t.x); line.setAttribute('y2', t.y);
            line.setAttribute('stroke', '#9ca3af'); line.setAttribute('stroke-width', '1');
            svg.appendChild(line);
          }
          for (const node of nodes) {
            const group = document.createElementNS('http://www.w3.org/2000/svg', 'g');
            group.style.cursor = 'pointer';
            group.onclick = () => window.webkit.messageHandlers.jamfMapper.postMessage({ nodeKey: node.id });
            const circle = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
            circle.setAttribute('cx', node.x); circle.setAttribute('cy', node.y); circle.setAttribute('r', 18);
            circle.setAttribute('fill', node.enabled === false ? '#a3a3a3' : (colors[node.type] || '#6b7280'));
            const text = document.createElementNS('http://www.w3.org/2000/svg', 'text');
            text.setAttribute('x', node.x + 24); text.setAttribute('y', node.y + 5); text.setAttribute('font-size', '12'); text.textContent = node.label;
            group.appendChild(circle); group.appendChild(text); svg.appendChild(group);
          }
        }

        window.renderGraph = function(payload) {
          if (!window.cytoscape) {
            renderFallback(payload);
            return;
          }
          document.getElementById('cy').style.display = 'block';
          document.getElementById('fallback').style.display = 'none';
          const elements = [...payload.nodes, ...payload.edges];
          if (!cy) {
            cy = cytoscape({
              container: document.getElementById('cy'),
              elements,
              wheelSensitivity: 0.18,
              style: [
                { selector: 'node', style: {
                  'background-color': ele => ele.data('enabled') === false ? '#a3a3a3' : (colors[ele.data('type')] || '#6b7280'),
                  'label': 'data(label)', 'font-size': 11, 'text-wrap': 'wrap', 'text-max-width': 120,
                  'color': '#1f2937', 'text-valign': 'bottom', 'text-halign': 'center',
                  'width': ele => ele.data('orphan') ? 22 : 30, 'height': ele => ele.data('orphan') ? 22 : 30
                }},
                { selector: 'edge', style: {
                  'curve-style': 'bezier', 'target-arrow-shape': 'triangle', 'line-color': '#9ca3af',
                  'target-arrow-color': '#9ca3af', 'width': 1.2, 'label': 'data(label)', 'font-size': 8,
                  'text-background-color': '#ffffff', 'text-background-opacity': 0.75
                }},
                { selector: '.highlight', style: { 'background-color': '#facc15', 'line-color': '#facc15', 'target-arrow-color': '#facc15', 'width': 3 } }
              ],
              layout: { name: 'cose', animate: false, nodeRepulsion: 90000, idealEdgeLength: 120 }
            });
            cy.on('tap', 'node', function(evt) {
              const node = evt.target;
              cy.elements().removeClass('highlight');
              node.closedNeighborhood().addClass('highlight');
              window.webkit.messageHandlers.jamfMapper.postMessage({ nodeKey: node.id() });
            });
            cy.on('dbltap', 'node', function(evt) {
              const root = evt.target;
              cy.elements().removeClass('highlight');
              let visited = {};
              function walk(n) {
                if (visited[n.id()]) return;
                visited[n.id()] = true;
                n.addClass('highlight');
                n.outgoers().addClass('highlight').targets().forEach(walk);
              }
              walk(root);
            });
          } else {
            cy.elements().remove();
            cy.add(elements);
            cy.layout({ name: 'cose', animate: false, nodeRepulsion: 90000, idealEdgeLength: 120 }).run();
          }
        }
      </script>
    </body>
    </html>
    """
}
