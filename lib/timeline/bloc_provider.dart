import "package:flutter/widgets.dart";
import "package:rivtrek/models/daily_stats.dart";
import "package:rivtrek/timeline/blocs/favorites_bloc.dart";
import 'package:rivtrek/timeline/search_manager.dart';
import 'package:rivtrek/timeline/timeline/timeline.dart';
import 'package:rivtrek/timeline/timeline/timeline_entry.dart';

/// This [InheritedWidget] wraps the whole app, and provides access
/// to the user's favorites through the [FavoritesBloc] 
/// and the [Timeline] object.
class BlocProvider extends InheritedWidget {
  final FavoritesBloc favoritesBloc;
  final Timeline timeline;
  final String? timelineUri;

  /// This widget is initialized when the app boots up, and thus loads the resources.
  /// The timeline.json file contains all the entries' data.
  /// Once those entries have been loaded, load also all the favorites.
  /// Lastly use the entries' references to load a local dictionary for the [SearchManager].
  BlocProvider(
      {Key? key,
      FavoritesBloc? fb,
      Timeline? t,
      required Widget child,
      TargetPlatform platform = TargetPlatform.iOS,
      List<DailyActivity>? activities,
      List<DailyWeather>? weathers,
      String? uri})
      : timeline = t ?? Timeline(platform),
        timelineUri = uri ?? "assets/timeline.json",
        favoritesBloc = fb ?? FavoritesBloc(),
        super(key: key, child: child) {
    if (activities != null) {
      timeline.loadFromActivities(activities, weathers ?? []).then((entries) {
        _initFromEntries(entries);
      });
    } else {
      timeline
          .loadFromBundle(timelineUri!)
          .then((List<TimelineEntry> entries) {
        _initFromEntries(entries);
      });
    }
  }

  void _initFromEntries(List<TimelineEntry> entries) {
    if (entries.isNotEmpty) {
      timeline.setViewport(
          start: entries.first.start,
          end: entries.last.end,
          animate: true);
    }
    /// Advance the timeline to its starting position.
    timeline.advance(0.0, false);

    /// All the entries are loaded, we can fill in the [favoritesBloc]...
    favoritesBloc.init(entries);
    /// ...and initialize the [SearchManager].
    SearchManager.init(entries);
  }

  @override
  updateShouldNotify(InheritedWidget oldWidget) => true;

  /// static accessor for the [FavoritesBloc]. 
  /// e.g. [ArticleWidget] retrieves the favorites information using this static getter.
  static FavoritesBloc favorites(BuildContext context) {
    BlocProvider? bp =
        context.dependOnInheritedWidgetOfExactType<BlocProvider>();
    FavoritesBloc bloc = bp!.favoritesBloc;
    return bloc;
  }

  /// static accessor for the [Timeline]. 
  /// e.g. [_MainMenuWidgetState.navigateToTimeline] uses this static getter to access build the [TimelineWidget].
  static Timeline getTimeline(BuildContext context) {
    BlocProvider? bp =
        context.dependOnInheritedWidgetOfExactType<BlocProvider>();
    Timeline? bloc = bp!.timeline;
    return bloc;
  }
}
