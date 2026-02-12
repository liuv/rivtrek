import "dart:async";
import "dart:io";

import 'package:flutter/cupertino.dart';
import "package:flutter/material.dart";
import 'package:flutter/services.dart';
import "package:flutter/widgets.dart";
import 'package:rive/rive.dart';
import "package:share/share.dart";
import 'package:rivtrek/timeline/bloc_provider.dart';
import 'package:rivtrek/timeline/main_menu/collapsible.dart';

import "package:rivtrek/timeline/main_menu/menu_data.dart";
import "package:rivtrek/timeline/main_menu/search_widget.dart";
import "package:rivtrek/timeline/main_menu/main_menu_section.dart";
import "package:rivtrek/timeline/main_menu/about_page.dart";
import "package:rivtrek/timeline/main_menu/favorites_page.dart";
import 'package:rivtrek/timeline/main_menu/thumbnail_detail_widget.dart';
import "package:rivtrek/timeline/search_manager.dart";
import "package:rivtrek/timeline/colors.dart";
import "package:rivtrek/timeline/timeline/timeline_entry.dart";
import 'package:rivtrek/timeline/timeline/timeline_widget.dart';

import '../../fitness_app_theme.dart';

/// The Main Page of the Timeline App.
///
/// This Widget lays out the search bar at the top of the page,
/// the three card-sections for accessing the main events on the Timeline,
/// and it'll provide on the bottom three links for quick access to your Favorites,
/// a Share Menu and the About Page.
class MainMenuWidget extends StatefulWidget {
  const MainMenuWidget({Key? key, this.animationController}) : super(key: key);
  final AnimationController? animationController;

  @override
  _MainMenuWidgetState createState() => _MainMenuWidgetState();
}

class _MainMenuWidgetState extends State<MainMenuWidget> {
  Animation<double>? topBarAnimation;

  final ScrollController scrollController = ScrollController();
  double topBarOpacity = 0.0;

  /// State is maintained for two reasons:
  ///
  /// 1. Search Functionality:
  /// When the search bar is tapped, the Widget view is filled with all the
  /// search info -- i.e. the [ListView] containing all the results.
  bool _isSearching = false;

  /// 2. Section Animations:
  /// Each card section contains a Flare animation that's playing in the background.
  /// These animations are paused when they're not visible anymore (e.g. when search is visible instead),
  /// and are played again once they're back in view.
  bool _isSectionActive = true;

  /// The [List] of search results that is displayed when searching.
  List<TimelineEntry> _searchResults = <TimelineEntry>[];

  /// [MenuData] is a wrapper object for the data of each Card section.
  /// This data is loaded from the asset bundle during [initState()]
  final MenuData _menu = MenuData();

  /// This is passed to the SearchWidget so we can handle text edits and display the search results on the main menu.
  final TextEditingController _searchTextController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  Timer? _searchTimer;

  cancelSearch() {
    if (_searchTimer != null && _searchTimer!.isActive) {
      /// Remove old timer.
      _searchTimer?.cancel();
      _searchTimer = null;
    }
  }

  /// Helper function which sets the [MenuItemData] for the [TimelineWidget].
  /// This will trigger a transition from the current menu to the Timeline,
  /// thus the push on the [Navigator], and by providing the [item] as
  /// a parameter to the [TimelineWidget] constructor, this widget will know
  /// where to scroll to.
  navigateToTimeline(MenuItemData item) {
    _pauseSection();
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (BuildContext context) =>
              TimelineWidget(item, BlocProvider.getTimeline(context)),
        ))
        .then(_restoreSection);
  }

  _restoreSection(v) => setState(() => _isSectionActive = true);

  _pauseSection() => setState(() => _isSectionActive = false);

  /// Used by the [_searchTextController] to properly update the state of this widget,
  /// and consequently the layout of the current view.
  updateSearch() {
    cancelSearch();
    if (!_isSearching) {
      setState(() {
        _searchResults = <TimelineEntry>[];
      });
      return;
    }
    String txt = _searchTextController.text.trim();

    /// Perform search.
    ///
    /// A [Timer] is used to prevent unnecessary searches while the user is typing.
    _searchTimer = Timer(Duration(milliseconds: txt.isEmpty ? 0 : 350), () {
      Set<TimelineEntry> res = SearchManager.init().performSearch(txt);
      setState(() {
        _searchResults = res.toList();
      });
    });
  }

  initState() {
    super.initState();
    topBarAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
            parent: widget.animationController!,
            curve: Interval(0, 0.5, curve: Curves.fastOutSlowIn)));

    scrollController.addListener(() {
      if (scrollController.offset >= 24) {
        if (topBarOpacity != 1.0) {
          setState(() {
            topBarOpacity = 1.0;
          });
        }
      } else if (scrollController.offset <= 24 &&
          scrollController.offset >= 0) {
        if (topBarOpacity != scrollController.offset / 24) {
          setState(() {
            topBarOpacity = scrollController.offset / 24;
          });
        }
      } else if (scrollController.offset <= 0) {
        if (topBarOpacity != 0.0) {
          setState(() {
            topBarOpacity = 0.0;
          });
        }
      }
    });

    /// The [_menu] loads a JSON file that's stored in the assets folder.
    /// This asset provides all the necessary information for the cards,
    /// such as labels, background colors, the background Flare animation asset,
    /// and for each element in the expanded card, the relative position on the [Timeline].
    _menu.loadFromBundle("assets/menu.json").then((bool success) {
      if (success) setState(() {}); // Load the menu.
    });

    _searchTextController.addListener(() {
      updateSearch();
    });

    _searchFocusNode.addListener(() {
      setState(() {
        _isSearching = _searchFocusNode.hasFocus;
        updateSearch();
      });
    });
  }

  /// A [WillPopScope] widget wraps the menu, so that before dismissing the whole app,
  /// search will be popped first. Otherwise the app will proceed as usual.
  Future<bool> _popSearch() {
    if (_isSearching) {
      setState(() {
        _searchFocusNode.unfocus();
        _searchTextController.clear();
        _isSearching = false;
      });
      return Future(() => false);
    } else {
      Navigator.of(context).pop(true);
      return Future(() => true);
    }
  }

  void _tapSearchResult(TimelineEntry entry) {
    navigateToTimeline(MenuItemData.fromEntry(entry));
  }

  @override
  Widget build(BuildContext context) {
    EdgeInsets devicePadding = MediaQuery.of(context).padding;

    List<Widget> tail = [];

    /// Check the current state before creating the layout for the menu (i.e. [tail]).
    ///
    /// If the app is searching, lay out the results.
    /// Otherwise, insert the menu information with all the various sections.
    if (_isSearching) {
      for (int i = 0; i < _searchResults.length; i++) {
        tail.add(RepaintBoundary(
            child: ThumbnailDetailWidget(_searchResults[i],
                hasDivider: i != 0, tapSearchResult: _tapSearchResult)));
      }
    } else {
      tail
        ..addAll(_menu.sections
            .map<Widget>((MenuSectionData section) => Container(
                margin: EdgeInsets.only(top: 20.0),
                child: MenuSection(
                  section.label ?? '',
                  section.backgroundColor,
                  section.textColor,
                  section.items,
                  navigateToTimeline,
                  _isSectionActive,
                  assetId: section.assetId,
                )))
            .toList(growable: false))
        ..add(Container(
          margin: EdgeInsets.only(top: 40.0, bottom: 22),
          height: 1.0,
          color: const Color.fromRGBO(151, 151, 151, 0.29),
        ))
        ..add(TextButton(
            onPressed: () {
              _pauseSection();
              Navigator.of(context)
                  .push(MaterialPageRoute(
                      builder: (BuildContext context) => FavoritesPage()))
                  .then(_restoreSection);
            },
            // color: Colors.transparent,
            style: TextButton.styleFrom(
              foregroundColor: Colors.transparent,
            ),
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Container(
                margin: EdgeInsets.only(right: 15.5),
                child: Image.asset("assets/heart_icon.png",
                    height: 20.0,
                    width: 20.0,
                    color: Colors.black.withOpacity(0.65)),
              ),
              Text(
                "个人收藏",
                style: TextStyle(
                    fontSize: 20.0,
                    fontFamily: "RobotoMedium",
                    color: Colors.black.withOpacity(0.65)),
              ),
            ])))
      ..add(
          SizedBox(
        height: 62 +
            MediaQuery.of(context).padding.bottom,
      ));
      // ..add(TextButton(
      //     onPressed: () => Share.share(
      //         "Check out The History of Everything! " + (Platform.isAndroid ? "https://play.google.com/store/apps/details?id=com.twodimensions.timeline" : "itms://itunes.apple.com/us/app/apple-store/id1441257460?mt=8")),
      //     style: TextButton.styleFrom(
      //       foregroundColor: Colors.transparent,
      //     ),
      //     child:
      //         Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      //       Container(
      //         margin: EdgeInsets.only(right: 15.5),
      //         child: Image.asset("assets/share_icon.png",
      //             height: 20.0,
      //             width: 20.0,
      //             color: Colors.black.withOpacity(0.65)),
      //       ),
      //       Text(
      //         "Share",
      //         style: TextStyle(
      //             fontSize: 20.0,
      //             fontFamily: "RobotoMedium",
      //             color: Colors.black.withOpacity(0.65)),
      //       )
      //     ])))
      // ..add(Padding(
      //   padding: const EdgeInsets.only(bottom: 30.0),
      //   child: TextButton(
      //       onPressed: () {
      //         _pauseSection();
      //         Navigator.of(context)
      //             .push(MaterialPageRoute(
      //                 builder: (BuildContext context) => AboutPage()))
      //             .then(_restoreSection);
      //       },
      //       style: TextButton.styleFrom(
      //         foregroundColor: Colors.transparent,
      //       ),
      //       child:
      //           Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      //         Container(
      //           margin: EdgeInsets.only(right: 15.5),
      //           child: Image.asset("assets/info_icon.png",
      //               height: 20.0,
      //               width: 20.0,
      //               color: Colors.black.withOpacity(0.65)),
      //         ),
      //         Text(
      //           "About",
      //           style: TextStyle(
      //               fontSize: 20.0,
      //               fontFamily: "RobotoMedium",
      //               color: Colors.black.withOpacity(0.65)),
      //         )
      //       ])),
      // ));
    }
    widget.animationController?.forward();

    /// Wrap the menu in a [WillPopScope] to properly handle a pop event while searching.
    /// A [SingleChildScrollView] is used to create a scrollable view for the main menu.
    /// This will contain a [Column] with a [Collapsible] header on top, and a [tail]
    /// that's built according with the state of this widget.
    return WillPopScope(
      onWillPop: _popSearch,
      child: Container(
        color: FitnessAppTheme.background,
        child: Column(
          children: <Widget>[
            getAppBarUI(),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                child: Padding(
                  padding: EdgeInsets.only(top: 0, left: 20, right: 20, bottom: 20),
                  // child: SingleChildScrollView(
                  //     padding: EdgeInsets.only(
                  //         top: 0, left: 20, right: 20, bottom: 20),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                                // Padding(
                                //     padding: EdgeInsets.only(top: 22.0),
                                //     child:
                                    SearchWidget(_searchFocusNode,
                                        _searchTextController)
                                // )
                              ] +
                              tail
                      ),
                  // ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget getAppBarUI() {
    return Column(
      children: <Widget>[
        AnimatedBuilder(
          animation: widget.animationController!,
          builder: (BuildContext context, Widget? child) {
            return FadeTransition(
              opacity: topBarAnimation!,
              child: Transform(
                transform: Matrix4.translationValues(
                    0.0, 30 * (1.0 - topBarAnimation!.value), 0.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: FitnessAppTheme.white.withOpacity(topBarOpacity),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(12.0),
                      bottomRight: Radius.circular(12.0),
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                          color: FitnessAppTheme.grey
                              .withOpacity(0.4 * topBarOpacity),
                          offset: const Offset(1.1, 1.1),
                          blurRadius: 10.0),
                    ],
                  ),
                  child: Column(
                    children: <Widget>[
                      SizedBox(
                        height: MediaQuery.of(context).padding.top,
                      ),
                      Padding(
                        padding: EdgeInsets.only(
                            left: 16,
                            right: 16,
                            top: 16 - 8.0 * topBarOpacity,
                            bottom: 12 - 8.0 * topBarOpacity),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(
                                  '纪章',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: FitnessAppTheme.fontName,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 22 + 6 - 6 * topBarOpacity,
                                    letterSpacing: 1.2,
                                    color: FitnessAppTheme.darkerText,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    ],
                  ),
                ),
              ),
            );
          },
        )
      ],
    );
  }
}
