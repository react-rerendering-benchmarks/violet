// This source code is a part of Project Violet.
// Copyright (C) 2020-2022. violet-team. Licensed under the Apache-2.0 License.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:auto_animated/auto_animated.dart';
import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tuple/tuple.dart';
import 'package:uuid/uuid.dart';
import 'package:violet/component/hitomi/hitomi_parser.dart';
import 'package:violet/component/hitomi/population.dart';
import 'package:violet/database/query.dart';
import 'package:violet/database/user/download.dart';
import 'package:violet/network/wrapper.dart' as http;
import 'package:violet/locale/locale.dart';
import 'package:violet/other/dialogs.dart';
import 'package:violet/pages/download/download_features_menu.dart';
import 'package:violet/pages/download/download_item_widget.dart';
import 'package:violet/pages/download/download_view_type.dart';
import 'package:violet/pages/search/search_type.dart';
import 'package:violet/pages/segment/filter_page.dart';
import 'package:violet/pages/segment/platform_navigator.dart';
import 'package:violet/script/script_manager.dart';
import 'package:violet/settings/settings.dart';
import 'package:violet/widgets/search_bar.dart';

typedef StringCallback = Future Function(String);

class DownloadPageManager {
  static bool downloadPageLoaded = false;
  static StreamController<String> taskController;
}

// This page must remain alive until the app is closed.
class DownloadPage extends StatefulWidget {
  @override
  _DownloadPageState createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage>
    with AutomaticKeepAliveClientMixin<DownloadPage> {
  @override
  bool get wantKeepAlive => true;

  ScrollController _scroll = ScrollController();
  List<DownloadItemModel> items = [];
  Map<int, DownloadItemModel> itemsMap = Map<int, DownloadItemModel>();
  List<DownloadItemModel> filterResult = [];
  Map<int, QueryResult> queryResults = Map<int, QueryResult>();
  FilterController _filterController =
      FilterController(heroKey: "downloadtype");
  ObjectKey _listKey = ObjectKey(Uuid().v4());

  @override
  void initState() {
    super.initState();
    refresh();
    // DownloadPageManager.appendTask = appendTask;
    DownloadPageManager.taskController = StreamController<String>();
    DownloadPageManager.taskController.stream.listen((event) {
      appendTask(event);
    });
  }

  @override
  void dispose() {
    super.dispose();
    DownloadPageManager.taskController.close();
  }

  void refresh() {
    Future.delayed(Duration(milliseconds: 500), () async {
      items = await (await Download.getInstance()).getDownloadItems();
      await _autoRecoveryFileName();
      await _buildQueryResults();
      _applyFilter();
      setState(() {});
    });
  }

  Future<void> _autoRecoveryFileName() async {
    /// For ios, the app encryption name is changed when you update the app.
    /// Therefore, it is necessary to correct this.
    if (!Platform.isIOS) return;

    /// Replace
    /// /var/mobile/Containers/Data/Application/<old-app-code>/Documents
    /// to
    /// /var/mobile/Containers/Data/Application/<new-app-code>/Documents

    final newPath = (await getApplicationDocumentsDirectory()).path;

    for (var item in items) {
      if (item.files() == null) continue;

      if (item.files() != null &&
          item.files().toLowerCase().contains(newPath.toLowerCase())) continue;
      if (item.path() != null &&
          item.path().toLowerCase().contains(newPath.toLowerCase())) continue;

      final oldPath = ((jsonDecode(item.files()) as List<dynamic>)[0] as String)
          .split('/')
          .take(8)
          .join('/');

      Map<String, dynamic> result = Map<String, dynamic>.from(item.result);

      if (item.files() != null)
        result['Files'] = item.files().replaceAll(oldPath, newPath);
      if (item.path() != null)
        result['Path'] = item.path().replaceAll(oldPath, newPath);
      item.result = result;

      await item.update();
    }
  }

  Future<void> _buildQueryResults() async {
    var articles = <Tuple2<int, int>>[];
    for (var item in items) {
      if (item.state() == 0 && int.tryParse(item.url()) != null) {
        articles.add(Tuple2<int, int>(item.id(), int.parse(item.url())));
        itemsMap[item.id()] = item;
      }
    }

    var queryRaw = 'SELECT * FROM HitomiColumnModel WHERE ';
    queryRaw += 'Id IN (' + articles.map((e) => e.item2).join(',') + ')';
    QueryManager.query(queryRaw).then((value) async {
      var qr = Map<int, QueryResult>();
      value.results.forEach((element) {
        qr[element.id()] = element;
      });

      var result = <Tuple2<int, QueryResult>>[];
      articles.forEach((element) async {
        if (qr[element.item2] == null) {
          try {
            var headers = await ScriptManager.runHitomiGetHeaderContent(
                element.item2.toString());
            var hh = await http.get(
              'https://ltn.hitomi.la/galleryblock/${element.item2}.html',
              headers: headers,
            );
            var article = await HitomiParser.parseGalleryBlock(hh.body);
            var meta = {
              'Id': element.item2,
              'Title': article['Title'],
              'Artists': article['Artists'].join('|'),
            };
            result.add(Tuple2<int, QueryResult>(
                element.item1, QueryResult(result: meta)));
            return;
          } catch (e, st) {}
        }
        result.add(Tuple2<int, QueryResult>(element.item1, qr[element.item2]));
      });

      result.forEach((element) {
        queryResults[element.item1] = element.item2;
      });
    });
  }

  Map<int, GlobalKey<DownloadItemWidgetState>> downloadItemWidgetKeys =
      Map<int, GlobalKey<DownloadItemWidgetState>>();
  ScrollController _scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final double statusBarHeight = MediaQuery.of(context).padding.top;
    DownloadPageManager.downloadPageLoaded = true;

    return Container(
      padding: EdgeInsets.only(top: statusBarHeight),
      child: GestureDetector(
        child: CustomScrollView(
          // key: key,
          // cacheExtent: height * 100,
          controller: _scroll,
          physics: const BouncingScrollPhysics(),
          slivers: <Widget>[
            SliverPersistentHeader(
              floating: true,
              delegate: AnimatedOpacitySliver(
                minExtent: 64 + 12.0,
                maxExtent: 64.0 + 12,
                searchBar: Stack(
                  children: <Widget>[
                    _urlBar(),
                    _features(),
                    _align(),
                  ],
                ),
              ),
            ),
            // _cachedPanel,
            _panel(),
          ],
        ),
      ),
    );
  }

  double lastWindowWidth;
  Widget _panel() {
    var windowWidth = lastWindowWidth = MediaQuery.of(context).size.width;

    if (Settings.downloadResultType == 0 || Settings.downloadResultType == 1) {
      var mm = Settings.downloadResultType == 0 ? 3 : 2;
      return SliverPadding(
          padding: EdgeInsets.fromLTRB(8, 0, 8, 16),
          sliver: SliverGrid(
            key: _listKey,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: Settings.useTabletMode ? mm * 2 : mm,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 3 / 4,
            ),
            delegate: SliverChildBuilderDelegate(
              (BuildContext context, int index) {
                var e = filterResult[filterResult.length - index - 1];
                if (!downloadItemWidgetKeys
                    .containsKey(filterResult[index].id()))
                  downloadItemWidgetKeys[filterResult[index].id()] =
                      GlobalKey<DownloadItemWidgetState>();
                return Align(
                  key: Key('dp' + e.id().toString() + e.url()),
                  alignment: Alignment.bottomCenter,
                  child: DownloadItemWidget(
                    key: downloadItemWidgetKeys[filterResult[index].id()],
                    initialStyle: DownloadListItem(
                      showDetail: false,
                      addBottomPadding: false,
                      width: (windowWidth - 4.0) / mm,
                    ),
                    item: e,
                    download: e.download,
                    refeshCallback: refresh,
                  ),
                );
              },
              childCount: filterResult.length,
            ),
          ));
    } else if (Settings.downloadResultType == 2 ||
        Settings.downloadResultType == 3) {
      if (Settings.useTabletMode ||
          MediaQuery.of(context).orientation == Orientation.landscape) {
        return SliverPadding(
          padding: EdgeInsets.fromLTRB(8, 0, 8, 16),
          sliver: LiveSliverGrid(
            key: _listKey,
            controller: _scrollController,
            showItemInterval: Duration(milliseconds: 50),
            showItemDuration: Duration(milliseconds: 150),
            visibleFraction: 0.001,
            itemCount: filterResult.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: (windowWidth / 2) / 130,
            ),
            itemBuilder: (context, index, animation) {
              var e = filterResult[filterResult.length - index - 1];
              if (!downloadItemWidgetKeys.containsKey(filterResult[index].id()))
                downloadItemWidgetKeys[filterResult[index].id()] =
                    GlobalKey<DownloadItemWidgetState>();
              return Align(
                key: Key('dp' + e.id().toString() + e.url()),
                alignment: Alignment.center,
                child: DownloadItemWidget(
                  key: downloadItemWidgetKeys[filterResult[index].id()],
                  initialStyle: DownloadListItem(
                    showDetail: Settings.downloadResultType == 3,
                    addBottomPadding: true,
                    width: windowWidth - 4.0,
                  ),
                  item: e,
                  download: e.download,
                  refeshCallback: refresh,
                ),
              );
            },
          ),
        );
      } else {
        return SliverList(
          key: _listKey,
          delegate: SliverChildListDelegate(
            filterResult.reversed.map((e) {
              if (!downloadItemWidgetKeys.containsKey(e.id()))
                downloadItemWidgetKeys[e.id()] =
                    GlobalKey<DownloadItemWidgetState>();
              return Align(
                key: Key('dp' + e.id().toString() + e.url()),
                alignment: Alignment.center,
                child: DownloadItemWidget(
                  key: downloadItemWidgetKeys[e.id()],
                  initialStyle: DownloadListItem(
                    showDetail: Settings.downloadResultType == 3,
                    addBottomPadding: true,
                    width: windowWidth - 4.0,
                  ),
                  item: e,
                  download: e.download,
                  refeshCallback: refresh,
                ),
              );
            }).toList(),
          ),
        );
      }
    }

    return null;
  }

  Widget _urlBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(8, 8, 72 + 64.0 + 8, 0),
      child: SizedBox(
        height: 64,
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(
              Radius.circular(4.0),
            ),
          ),
          elevation: !Settings.themeFlat ? 100 : 0,
          clipBehavior: Clip.antiAliasWithSaveLayer,
          child: Stack(
            children: <Widget>[
              Column(
                children: <Widget>[
                  Material(
                    color: Settings.themeWhat
                        ? Settings.themeBlack
                            ? const Color(0xFF141414)
                            : Colors.grey.shade900.withOpacity(0.4)
                        : Colors.grey.shade200.withOpacity(0.4),
                    child: ListTile(
                      title: TextFormField(
                        cursorColor: Colors.black,
                        decoration: InputDecoration(
                            border: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            contentPadding: EdgeInsets.only(
                                left: 15, bottom: 11, top: 11, right: 15),
                            hintText: Translations.of(context).trans('addurl')),
                      ),
                      leading: SizedBox(
                        width: 25,
                        height: 25,
                        child: Icon(MdiIcons.instagram),
                      ),
                    ),
                  )
                ],
              ),
              Positioned(
                left: 0.0,
                top: 0.0,
                bottom: 0.0,
                right: 0.0,
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: () async {
                      if (!Settings.useInnerStorage &&
                          (await SharedPreferences.getInstance())
                                  .getBool('checkauthalready') ==
                              null) {
                        await (await SharedPreferences.getInstance())
                            .setBool('checkauthalready', true);
                        if (await Permission.storage.request() ==
                            PermissionStatus.denied) {
                          await showOkDialog(context,
                              "You cannot use downloader, if you not allow external storage permission.");
                          return;
                        }
                      }
                      Widget yesButton = TextButton(
                        style:
                            TextButton.styleFrom(primary: Settings.majorColor),
                        child: Text(Translations.of(context).trans('ok')),
                        onPressed: () {
                          Navigator.pop(context, true);
                        },
                      );
                      Widget noButton = TextButton(
                        style:
                            TextButton.styleFrom(primary: Settings.majorColor),
                        child: Text(Translations.of(context).trans('cancel')),
                        onPressed: () {
                          Navigator.pop(context, false);
                        },
                      );
                      TextEditingController text = TextEditingController();
                      var dialog = await showDialog(
                        useRootNavigator: false,
                        context: context,
                        builder: (BuildContext context) => AlertDialog(
                          contentPadding: EdgeInsets.fromLTRB(12, 0, 12, 0),
                          title:
                              Text(Translations.of(context).trans('writeurl')),
                          content: TextField(
                            controller: text,
                            autofocus: true,
                          ),
                          actions: [yesButton, noButton],
                        ),
                      );
                      if (int.parse(text.text) == null) {
                        await showOkDialog(context, "숫자만 입력해야 합니다!");
                        return;
                      }
                      if (dialog == true) {
                        await appendTask(text.text);
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _features() {
    double width = MediaQuery.of(context).size.width;
    return Container(
      padding: EdgeInsets.fromLTRB(width - 8 - 64 - 64 - 8, 8, 8, 0),
      child: SizedBox(
        height: 64,
        child: Hero(
          tag: "features",
          child: Card(
            color: Settings.themeWhat
                ? Settings.themeBlack
                    ? const Color(0xFF141414)
                    : Color(0xFF353535)
                : Colors.grey.shade100,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(
                Radius.circular(4.0),
              ),
            ),
            elevation: !Settings.themeFlat ? 100 : 0,
            clipBehavior: Clip.antiAliasWithSaveLayer,
            child: InkWell(
              child: SizedBox(
                height: 64,
                width: 64,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    Icon(
                      MdiIcons.hammerWrench,
                      color: Colors.grey,
                    ),
                  ],
                ),
              ),
              onTap: _featuresOnTap,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _featuresOnTap() async {
    var rtype = Settings.downloadResultType;
    Navigator.of(context)
        .push(PageRouteBuilder(
      opaque: false,
      transitionDuration: Duration(milliseconds: 500),
      transitionsBuilder: (BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation, Widget wi) {
        return FadeTransition(opacity: animation, child: wi);
      },
      pageBuilder: (_, __, ___) => DownloadFeaturesMenu(),
      barrierColor: Colors.black12,
      barrierDismissible: true,
    ))
        .then((value) async {
      if (value == null) return;

      if (value == 0)
        downloadItemWidgetKeys
            .forEach((key, value) => value.currentState.retryWhenRequired());
      else if (value == 1)
        downloadItemWidgetKeys
            .forEach((key, value) => value.currentState.recovery());
    });
  }

  Widget _align() {
    double width = MediaQuery.of(context).size.width;
    return Container(
      padding: EdgeInsets.fromLTRB(width - 8 - 64, 8, 8, 0),
      child: SizedBox(
        height: 64,
        child: Hero(
          tag: "downloadtype",
          child: Card(
            color: Settings.themeWhat
                ? Settings.themeBlack
                    ? const Color(0xFF141414)
                    : Color(0xFF353535)
                : Colors.grey.shade100,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(
                Radius.circular(4.0),
              ),
            ),
            elevation: !Settings.themeFlat ? 100 : 0,
            clipBehavior: Clip.antiAliasWithSaveLayer,
            child: InkWell(
              child: SizedBox(
                height: 64,
                width: 64,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    Icon(
                      MdiIcons.formatListText,
                      color: Colors.grey,
                    ),
                  ],
                ),
              ),
              onTap: _alignOnTap,
              onLongPress: _alignLongPress,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _alignOnTap() async {
    var rtype = Settings.downloadResultType;
    Navigator.of(context)
        .push(PageRouteBuilder(
      opaque: false,
      transitionDuration: Duration(milliseconds: 500),
      transitionsBuilder: (BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation, Widget wi) {
        return FadeTransition(opacity: animation, child: wi);
      },
      pageBuilder: (_, __, ___) => DownloadViewType(),
      barrierColor: Colors.black12,
      barrierDismissible: true,
    ))
        .then((value) async {
      if (rtype != Settings.downloadResultType) {
        downloadItemWidgetKeys.forEach((key, value) =>
            downloadItemWidgetKeys[key] = GlobalKey<DownloadItemWidgetState>());
        await Future.delayed(Duration(milliseconds: 50), () {
          setState(() {});
        });
      }
    });
  }

  Future<void> _alignLongPress() async {
    PlatformNavigator.navigateFade(
      context,
      Provider<FilterController>.value(
        value: _filterController,
        child: FilterPage(
          queryResult: queryResults.entries.map((e) => e.value).toList(),
        ),
      ),
    ).then((value) {
      _applyFilter();
    });
  }

  void _applyFilter() {
    var result = <int>[];
    var isOr = _filterController.isOr;
    queryResults.entries.forEach((element) {
      // 1: Pending
      // 2: Extracting
      // 3: Downloading
      // 4: Post Processing
      if (1 <= itemsMap[element.key].state() &&
          itemsMap[element.key].state() <= 4) {
        result.add(element.key);
        return;
      }

      // key := <group>:<name>
      var succ = !_filterController.isOr;
      _filterController.tagStates.forEach((key, value) {
        if (!value) return;

        // Check match just only one
        if (succ == isOr) return;

        // Get db column name from group
        var split = key.split('|');
        var dbColumn = prefix2Tag(split[0]);

        // There is no matched db column name
        if (element.value.result[dbColumn] == null && !isOr) {
          succ = false;
          return;
        }

        // If Single Tag
        if (!isSingleTag(split[0])) {
          var tag = split[1];
          if (['female', 'male'].contains(split[0]))
            tag = '${split[0]}:${split[1]}';
          if ((element.value.result[dbColumn] as String).contains('|$tag|') ==
              isOr) succ = isOr;
        }

        // If Multitag
        else if ((element.value.result[dbColumn] as String == split[1]) == isOr)
          succ = isOr;
      });
      if (succ) result.add(element.key);
    });

    if (_filterController.tagStates.isNotEmpty)
      filterResult = result.map((e) => itemsMap[e]).toList();
    else
      filterResult = items;

    if (_filterController.isPopulationSort)
      Population.sortByPopulationDownloadItem(filterResult);

    setState(() {});
  }

  static String prefix2Tag(String prefix) {
    switch (prefix) {
      case 'artist':
        return 'Artists';
      case 'group':
        return 'Groups';
      case 'language':
        return 'Language';
      case 'character':
        return 'Characters';
      case 'series':
        return 'Series';
      case 'class':
        return 'Class';
      case 'type':
        return 'Type';
      case 'uploader':
        return 'Uploader';
      case 'tag':
      case 'female':
      case 'male':
        return 'Tags';
    }
    return '';
  }

  static bool isSingleTag(String prefix) {
    switch (prefix) {
      case 'language':
      case 'class':
      case 'type':
      case 'uploader':
        return true;
      case 'artist':
      case 'group':
      case 'character':
      case 'tag':
      case 'female':
      case 'male':
      case 'series':
        return false;
    }
    return null;
  }

  Future<void> appendTask(String url) async {
    var item = await (await Download.getInstance()).createNew(url);
    item.download = true;
    items.add(item);
    itemsMap[item.id()] = item;
    await _appendQueryResults(url);
    _applyFilter();
  }

  Future<void> _appendQueryResults(String url) async {
    if (int.tryParse(url) == null) return;

    var queryRaw = 'SELECT * FROM HitomiColumnModel WHERE ';
    queryRaw += 'Id = $url';

    var qm = await QueryManager.query(queryRaw);

    if (qm.results.isEmpty) return;

    queryResults[int.parse(url)] = qm.results.first;
  }
}
