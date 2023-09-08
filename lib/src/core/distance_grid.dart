import 'dart:math';

class CellEntry<T> {
  final T obj;
  final Point point;

  const CellEntry(this.obj, this.point);

  @override
  bool operator ==(Object other) {
    return other is CellEntry<T> && other.obj == obj;
  }

  @override
  int get hashCode => obj.hashCode;
}

class GridKey {
  final int row;
  final int col;

  GridKey(this.row, this.col);

  @override
  bool operator ==(Object other) {
    return other is GridKey && other.row == row && other.col == col;
  }

  @override
  int get hashCode => Object.hash(row, col);
}

class DistanceGrid<T> {
  final int cellSize;

  final int _sqCellSize;
  final Map<GridKey, List<CellEntry<T>>> _grid = {};
  final Map<T, GridKey> _objectPoint = {};

  DistanceGrid(int cellSize)
      : cellSize = cellSize > 0 ? cellSize : 1,
        _sqCellSize = cellSize * cellSize;

  void clear() {
    _grid.clear();
    _objectPoint.clear();
  }

  void addObject(T obj, Point point) {
    assert(!_objectPoint.containsKey(obj));
    final x = _getCoord(point.x), y = _getCoord(point.y);
    final key = GridKey(y, x);
    final cell = _grid[key] ??= [];

    _objectPoint[obj] = key;
    cell.add(CellEntry<T>(obj, point));
  }

  void updateObject(T obj, Point point) {
    removeObject(obj);
    addObject(obj, point);
  }

  // Returns true if the object was found
  bool removeObject(T obj) {
    final key = _objectPoint.remove(obj);
    if (key == null) return false;

    // Object existed in the _objectPoint map, thus must exist in the grid.
    final cell = _grid[key]!;
    cell.removeWhere((e) => e.obj == obj);
    if (cell.isEmpty) {
      _grid.remove(key);
    }
    return true;
  }

  void eachObject(Function(T) fn) {
    for (final cell in _grid.values) {
      for (final entry in cell) {
        fn(entry.obj);
      }
    }
  }

  T? getNearObject(Point point) {
    final x = _getCoord(point.x), y = _getCoord(point.y);
    double closestDistSq = _sqCellSize.toDouble();
    T? closest;

    // Checks rows and columns with index +/- 1.
    for (var i = y - 1; i <= y + 1; i++) {
      for (var j = x - 1; j <= x + 1; j++) {
        final cell = _grid[GridKey(i, j)];
        if (cell != null) {
          for (final entry in cell) {
            final dist = entry.point.squaredDistanceTo(point);
            if (dist <= closestDistSq) {
              closestDistSq = dist.toDouble();
              closest = entry.obj;
            }
          }
        }
      }
    }
    return closest;
  }

  int _getCoord(num x) => x ~/ cellSize;
}
