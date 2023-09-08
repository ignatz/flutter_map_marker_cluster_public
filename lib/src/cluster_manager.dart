import 'dart:ui';
import 'dart:math' as math;

import 'package:flutter_map/plugin_api.dart';
import 'package:flutter_map_marker_cluster/src/core/distance_grid.dart';
import 'package:flutter_map_marker_cluster/src/map_calculator.dart';
import 'package:flutter_map_marker_cluster/src/node/marker_cluster_node.dart';
import 'package:flutter_map_marker_cluster/src/node/marker_node.dart';
import 'package:flutter_map_marker_cluster/src/node/marker_or_cluster_node.dart';

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

  void clear() {
    for (final grid in _gridByZoom) {
      grid.clear();
    }
  }
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

  void addLayer(MarkerNode marker, int disableClusteringAtZoom, int maxZoom,
      int minZoom) {
    final int start = math.min(disableClusteringAtZoom + 1, maxZoom).toInt();
    for (int zoom = start; zoom >= minZoom; zoom--) {
      // for (int zoom = maxZoom; zoom >= minZoom; zoom--) {
      final markerPoint =
          mapCalculator.project(marker.point, zoom: zoom.toDouble());
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

  void recalculateTopClusterLevelProperties() {
    _topClusterLevel.recalculate(recursively: true);
    _gridUnclustered.clear();
    _gridClusters.clear();
  }

  void recursivelyFromTopClusterLevel(
          int zoomLevel,
          int disableClusteringAtZoom,
          LatLngBounds recursionBounds,
          Function(MarkerOrClusterNode) fn) =>
      _topClusterLevel.recursively(
          zoomLevel, disableClusteringAtZoom, recursionBounds, fn);
}
