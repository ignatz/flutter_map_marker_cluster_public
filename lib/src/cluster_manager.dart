import 'dart:ui';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:flutter_map_marker_cluster/src/core/distance_grid.dart';
import 'package:flutter_map_marker_cluster/src/map_calculator.dart';
import 'package:flutter_map_marker_cluster/src/node/marker_cluster_node.dart';
import 'package:flutter_map_marker_cluster/src/node/marker_node.dart';
import 'package:flutter_map_marker_cluster/src/node/marker_or_cluster_node.dart';
import 'package:rbush/rbush.dart';

class DistanceGridByZoom<T> {
  final int minZoom;
  final int maxZoom;
  final List<DistanceGrid<T>> _gridByZoom;

  DistanceGridByZoom({
    required this.minZoom,
    required this.maxZoom,
    required int maxClusterRadius,
  }) : _gridByZoom = List<DistanceGrid<T>>.generate(maxZoom - minZoom + 1, (_) {
          return DistanceGrid<T>(maxClusterRadius);
        }, growable: false);

  DistanceGrid<T> operator [](int i) => _gridByZoom[i - minZoom];
}

class ClusterManager {
  final MapCalculator mapCalculator;
  final AnchorPos? anchorPos;
  final Size predefinedSize;
  final Size Function(List<Marker>)? computeSize;

  late final DistanceGridByZoom<MarkerClusterNode> _gridClusters;
  late final DistanceGridByZoom<MarkerNode> _gridUnclustered;
  late MarkerClusterNode _topClusterLevel;

  MarkerClusterNode? spiderfyCluster;

  ClusterManager._({
    required this.mapCalculator,
    required this.anchorPos,
    required this.predefinedSize,
    required this.computeSize,
    required DistanceGridByZoom<MarkerClusterNode> gridClusters,
    required DistanceGridByZoom<MarkerNode> gridUnclustered,
    required MarkerClusterNode topClusterLevel,
  })  : _gridClusters = gridClusters,
        _gridUnclustered = gridUnclustered,
        _topClusterLevel = topClusterLevel;

  factory ClusterManager.initialize({
    required MapCalculator mapCalculator,
    required AnchorPos? anchorPos,
    required Size predefinedSize,
    required Size Function(List<Marker>)? computeSize,
    required int minZoom,
    required int maxZoom,
    required int maxClusterRadius,
  }) {
    final gridClusters = DistanceGridByZoom<MarkerClusterNode>(
        minZoom: minZoom, maxZoom: maxZoom, maxClusterRadius: maxClusterRadius);
    final gridUnclustered = DistanceGridByZoom<MarkerNode>(
        minZoom: minZoom, maxZoom: maxZoom, maxClusterRadius: maxClusterRadius);

    final topClusterLevel = MarkerClusterNode(
      anchorPos: anchorPos,
      zoom: minZoom - 1,
      predefinedSize: predefinedSize,
      computeSize: computeSize,
    );

    return ClusterManager._(
      anchorPos: anchorPos,
      mapCalculator: mapCalculator,
      predefinedSize: predefinedSize,
      computeSize: computeSize,
      gridClusters: gridClusters,
      gridUnclustered: gridUnclustered,
      topClusterLevel: topClusterLevel,
    );
  }

  bool isSpiderfyCluster(MarkerClusterNode cluster) {
    return spiderfyCluster != null &&
        spiderfyCluster!.bounds.center == cluster.bounds.center;
  }

  RBushElement<MarkerNode> toElement(MarkerNode marker, int zoom) {
    final point = mapCalculator.project(marker.point, zoom: zoom.toDouble());
    return RBushElement<MarkerNode>(
      minX: point.x.toDouble(),
      maxX: point.x.toDouble(),
      minY: point.y.toDouble(),
      maxY: point.y.toDouble(),
      data: marker,
    );
  }

  CustomPoint<double> toCellCenter(CustomPoint<double> p, int maxDistance) {
    final origin = CustomPoint<int>(p.x ~/ maxDistance, p.y ~/ maxDistance);
    return CustomPoint<double>(origin.x * maxDistance + maxDistance / 2,
        origin.y * maxDistance + maxDistance / 2);
  }

  RBushBox toBox(CustomPoint<double> p, int maxDistance) {
    final center = toCellCenter(p, maxDistance);
    return RBushBox(
      minX: center.x - maxDistance / 2,
      maxX: center.x + maxDistance / 2,
      minY: center.y - maxDistance / 2,
      maxY: center.y + maxDistance / 2,
    );
  }

  void addLayers(
    List<MarkerNode> markers,
    int disableClusteringAtZoom,
    int maxZoom,
    int minZoom,
    int maxClusterRadius,
  ) {
    final elements = List.generate(
        markers.length, (int index) => toElement(markers[index], maxZoom));

    final tree = RBush<MarkerNode>(16);
    tree.load(elements);

    final maxDepth = maxZoom - minZoom;
    assert(maxDepth >= 0);

    LatLng? recurse(
      int depth,
      MarkerClusterNode parent,
      List<RBushElement<MarkerNode>> elements,
    ) {
      final int zoom = minZoom + depth;
      // print('$depth $zoom $minZoom');
      final int maxDistance =
          maxClusterRadius * math.pow(2, maxDepth - depth).toInt();

      final Set<RBushElement<MarkerNode>> pending = elements.toSet();
      // print('elements: ${elements.length}');
      final points = <LatLng>[];
      while (pending.isNotEmpty) {
        final element = pending.first;
        final point = CustomPoint<double>(element.maxX, element.maxY);

        final box = toBox(point, maxDistance);
        // Convert to set because the search result sometimes contains duplicates :/.
        final List<RBushElement<MarkerNode>> neighbors =
            tree.search(box).toSet().toList();
        if (neighbors.isEmpty) throw 'wtf';

        // DEBUG
        for (final neighbor in neighbors) {
          final point1 =
              mapCalculator.project(element.data.point, zoom: zoom.toDouble());
          final point2 =
              mapCalculator.project(neighbor.data.point, zoom: zoom.toDouble());

          final dx = (point1.x - point2.x).abs();
          final dy = (point1.y - point2.y).abs();
          if (dx > maxClusterRadius || dy > maxClusterRadius) {
            throw 'too large ${maxClusterRadius} ${dx} ${dy}';
          }
        }
        // DEBUG

        if (zoom >= disableClusteringAtZoom || neighbors.length == 1) {
          // Stop the clustering.
          for (final neighbor in neighbors) {
            final marker = neighbor.data;
            final success = pending.remove(neighbor);
            if (!success) throw 'fail1';

            parent.addChild(marker, marker.point);
            points.add(marker.point);
          }
        } else {
          // Continue the clustering.
          // pending.removeAll(neighbors);
          for (final neighbor in neighbors) {
            final success = pending.remove(neighbor);
            if (!success) throw 'fail2';
          }

          final markers = neighbors.map((n) => n.data).toList();
          final bounds =
              LatLngBounds.fromPoints(markers.map((m) => m.point).toList());

          final cluster = MarkerClusterNode(
            zoom: zoom,
            anchorPos: anchorPos,
            predefinedSize: predefinedSize,
            computeSize: computeSize,
          );

          final center = recurse(depth + 1, cluster, neighbors)!;

          parent.addChild(cluster, center);
          points.add(center);
          // print('add cluster: $depth $zoom ${markers.length}');
        }
      }

      if (points.isNotEmpty) {
        return LatLngBounds.fromPoints(points).center;
      }
      return null;
    }

    final root = _topClusterLevel;
    recurse(0, root, elements);
  }

  void addLayer(MarkerNode marker, int disableClusteringAtZoom, int maxZoom,
      int minZoom) {
    for (var zoom = maxZoom; zoom >= minZoom; zoom--) {
      final markerPoint =
          mapCalculator.project(marker.point, zoom: zoom.toDouble());

      // print('$zoom ${markerPoint}');

      if (zoom <= disableClusteringAtZoom) {
        // try find a cluster close by
        final cluster = _gridClusters[zoom].getNearObject(markerPoint);
        if (cluster != null) {
          cluster.addChild(marker, marker.point);
          return;
        }

        final closest = _gridUnclustered[zoom].getNearObject(markerPoint);
        if (closest != null) {
          final parent = closest.parent!;
          parent.removeChild(closest);

          // final closestPoint =
          //     mapCalculator.project(closest.point, zoom: zoom.toDouble());
          // final distance = closestPoint.distanceTo(markerPoint);
          // print('distance $distance');

          final newCluster = MarkerClusterNode(
            zoom: zoom,
            anchorPos: anchorPos,
            predefinedSize: predefinedSize,
            computeSize: computeSize,
          )
            ..addChild(closest, closest.point)
            ..addChild(marker, closest.point);

          _gridClusters[zoom].addObject(
            newCluster,
            mapCalculator.project(
              newCluster.bounds.center,
              zoom: zoom.toDouble(),
            ),
          );

          // First create any new intermediate parent clusters that don't exist
          var lastParent = newCluster;
          for (var z = zoom - 1; z > parent.zoom; z--) {
            final newParent = MarkerClusterNode(
              zoom: z,
              anchorPos: anchorPos,
              predefinedSize: predefinedSize,
              computeSize: computeSize,
            );
            newParent.addChild(
              lastParent,
              lastParent.bounds.center,
            );
            lastParent = newParent;
            _gridClusters[z].addObject(
              lastParent,
              mapCalculator.project(
                closest.point,
                zoom: z.toDouble(),
              ),
            );
          }
          parent.addChild(lastParent, lastParent.bounds.center);

          _removeFromNewPosToMyPosGridUnclustered(closest, zoom, minZoom);
          return;
        }
      }

      _gridUnclustered[zoom].addObject(marker, markerPoint);
    }

    //Didn't get in anything, add us to the top
    _topClusterLevel.addChild(marker, marker.point);
  }

  void _removeFromNewPosToMyPosGridUnclustered(
      MarkerNode marker, int zoom, int minZoom) {
    for (; zoom >= minZoom; zoom--) {
      if (!_gridUnclustered[zoom].removeObject(marker)) {
        break;
      }
    }
  }

  void recalculateTopClusterLevelProperties() =>
      _topClusterLevel.recalculate(recursively: true);

  void recursivelyFromTopClusterLevel(
          int zoomLevel,
          int disableClusteringAtZoom,
          LatLngBounds recursionBounds,
          Function(MarkerOrClusterNode) fn) =>
      _topClusterLevel.recursively(
          zoomLevel, disableClusteringAtZoom, recursionBounds, fn);
}
