import 'package:flutter/material.dart';

/// A reusable widget that wraps a ListView with pull-to-refresh functionality
class RefreshableList extends StatelessWidget {
  final Future<void> Function() onRefresh;
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final ScrollPhysics? physics;

  const RefreshableList({
    Key? key,
    required this.onRefresh,
    required this.child,
    this.padding,
    this.physics,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: child,
    );
  }
}

/// A reusable widget that wraps a ListView.builder with pull-to-refresh functionality
class RefreshableListView extends StatelessWidget {
  final Future<void> Function() onRefresh;
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;
  final EdgeInsetsGeometry? padding;
  final ScrollPhysics? physics;
  final bool addAutomaticKeepAlives;
  final bool addRepaintBoundaries;

  const RefreshableListView({
    Key? key,
    required this.onRefresh,
    required this.itemCount,
    required this.itemBuilder,
    this.padding,
    this.physics,
    this.addAutomaticKeepAlives = true,
    this.addRepaintBoundaries = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: padding,
        physics: physics,
        itemCount: itemCount,
        itemBuilder: itemBuilder,
        addAutomaticKeepAlives: addAutomaticKeepAlives,
        addRepaintBoundaries: addRepaintBoundaries,
      ),
    );
  }
}

/// A reusable widget that wraps a ReorderableListView.builder with pull-to-refresh functionality
class RefreshableReorderableListView extends StatelessWidget {
  final Future<void> Function() onRefresh;
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;
  final void Function(int, int) onReorder;
  final EdgeInsets? padding;
  final ScrollPhysics? physics;

  const RefreshableReorderableListView({
    Key? key,
    required this.onRefresh,
    required this.itemCount,
    required this.itemBuilder,
    required this.onReorder,
    this.padding,
    this.physics,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ReorderableListView.builder(
        padding: padding,
        physics: physics,
        itemCount: itemCount,
        itemBuilder: itemBuilder,
        onReorder: onReorder,
      ),
    );
  }
} 