import json
import numpy as np
from pyproj import Geod
import heapq

def get_line_length(coords):
    if len(coords) < 2: return 0
    geod = Geod(ellps="WGS84")
    lons, lats = [p[0] for p in coords], [p[1] for p in coords]
    _, _, dists = geod.inv(lons[:-1], lats[:-1], lons[1:], lats[1:])
    return np.sum(dists)

def get_dist(p1, p2):
    geod = Geod(ellps="WGS84")
    _, _, d = geod.inv(p1[0], p1[1], p2[0], p2[1])
    return d

with open('tools/松花江 000304728411.geojson', 'r') as f:
    data = json.load(f)

segments = data['coordinates']
print(f"Number of segments: {len(segments)}")

nodes = []
edges = []

for i, seg in enumerate(segments):
    l = get_line_length(seg)
    print(f"Seg {i}: {l/1000:.2f} km, Start: {seg[0]}, End: {seg[-1]}")
    
    u = (round(seg[0][0], 6), round(seg[0][1], 6))
    v = (round(seg[-1][0], 6), round(seg[-1][1], 6))
    
    nodes.append(u)
    nodes.append(v)
    edges.append((u, v, l, i, False))
    edges.append((v, u, l, i, True))

unique_nodes = list(set(nodes))
print(f"Unique nodes: {len(unique_nodes)}")

start_node = min(unique_nodes, key=lambda x: x[0])
end_node = max(unique_nodes, key=lambda x: x[0])

print(f"Start node (West): {start_node}")
print(f"End node (East): {end_node}")

# Dijkstra
distances = {node: float('inf') for node in unique_nodes}
distances[start_node] = 0
pq = [(0, start_node)]
pre = {}

while pq:
    d, u = heapq.heappop(pq)
    if d > distances[u]: continue
    
    for u_edge, v_edge, w, idx, rev in edges:
        if u_edge == u:
            if d + w < distances[v_edge]:
                distances[v_edge] = d + w
                pre[v_edge] = (u, idx, rev)
                heapq.heappush(pq, (distances[v_edge], v_edge))

if distances[end_node] == float('inf'):
    print("No path found!")
else:
    print(f"Shortest path length: {distances[end_node]/1000:.2f} km")
