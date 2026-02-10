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

total = 0
count = 0
for f in data['features']:
    if f['geometry']['type'] == 'LineString':
        l = get_line_length(f['geometry']['coordinates'])
        total += l
        count += 1

print(f"Total features: {len(data['features'])}")
print(f"LineString count: {count}")
print(f"Sum of all lengths: {total/1000:.2f} km")
