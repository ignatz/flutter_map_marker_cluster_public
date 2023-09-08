import 'package:flutter/widgets.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:flutter_map_marker_cluster/src/node/marker_or_cluster_node.dart';
import 'package:latlong2/latlong.dart';

class MarkerNode extends MarkerOrClusterNode implements Marker {
  final Marker marker;

  MarkerNode(this.marker) : super(parent: null);

  @override
  Key? get key => marker.key;

  @override
  WidgetBuilder get builder => marker.builder;

  @override
  double get height => marker.height;

  @override
  LatLng get point => marker.point;

  @override
  double get width => marker.width;

  @override
  bool? get rotate => marker.rotate;

  @override
  AlignmentGeometry? get rotateAlignment => marker.rotateAlignment;

  @override
  Offset? get rotateOrigin => marker.rotateOrigin;

  @override
  AnchorPos? get anchorPos => marker.anchorPos;

  @override
  Bounds<double> pixelBounds(FlutterMapState map) {
    final pixelPoint = map.project(point);

    final anchor = Anchor.fromPos(
        anchorPos ?? AnchorPos.align(AnchorAlign.center), width, height);

    final rightPortion = width - anchor.left;
    final leftPortion = anchor.left;
    final bottomPortion = height - anchor.top;
    final topPortion = anchor.top;

    final ne =
        CustomPoint<double>(pixelPoint.x - rightPortion, pixelPoint.y + topPortion);
    final sw =
        CustomPoint<double>(pixelPoint.x + leftPortion, pixelPoint.y - bottomPortion);

    return Bounds<double>(ne, sw);
  }
}
