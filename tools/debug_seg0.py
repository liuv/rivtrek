import json
from pyproj import Geod
import numpy as np

def get_line_length(coords):
    if len(coords) < 2: return 0
    geod = Geod(ellps="WGS84")
    lons, lats = [p[0] for p in coords], [p[1] for p in coords]
    _, _, dists = geod.inv(lons[:-1], lats[:-1], lons[1:], lats[1:])
    return np.sum(dists)

with open('tools/松花江 000304728411.geojson', 'r') as f:
    data = json.load(f)

seg0 = data['coordinates'][0]
print(f"Seg 0 point count: {len(seg0)}")

# Check for duplicates
unique_pts = set()
dupes = 0
for p in seg0:
    k = (round(p[0], 6), round(p[1], 6))
    if k in unique_pts:
        dupes += 1
    unique_pts.add(k)
print(f"Duplicate points: {dupes}")

# Check for "back and forth"
back_forth = 0
for i in range(len(seg0)-2):
    p1, p2, p3 = seg0[i], seg0[i+1], seg0[i+2]
    d12 = get_line_length([p1, p2])
    d23 = get_line_length([p2, p3])
    d13 = get_line_length([p1, p3])
    if d13 < (d12 + d23) * 0.1: # If p3 is very close to p1
        back_forth += 1
print(f"Possible back-and-forth nodes: {back_forth}")
