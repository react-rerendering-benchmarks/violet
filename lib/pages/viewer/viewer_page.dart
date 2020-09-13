// This source code is a part of Project Violet.
// Copyright (C) 2020. violet-team. Licensed under the Apache-2.0 License.

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:provider/provider.dart';
import 'package:violet/database/user/record.dart';
import 'package:violet/locale/locale.dart';
import 'package:violet/other/dialogs.dart';
import 'package:violet/pages/viewer/viewer_page_provider.dart';
import 'package:violet/settings/settings.dart';

int currentPage = 0;

class ViewerPage extends StatelessWidget {
  ViewerPage();

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () {
        Navigator.pop(context, currentPage);
        return new Future(() => false);
      },
      child: _VerticalImageViewer(),
    );
  }
}

enum _ViewAppBarAction {
  toggleViewer,
  toggleRightToLeft,
  toggleScrollVertical,
}

class _VerticalImageViewer extends StatefulWidget {
  @override
  __VerticalImageViewerState createState() => __VerticalImageViewerState();
}

class __VerticalImageViewerState extends State<_VerticalImageViewer>
    with SingleTickerProviderStateMixin {
  ViewerPageProvider _pageInfo;
  Timer _clearTimer;
  List<bool> _loaded;
  List<double> _cachedHeight;
  ScrollController _scroll = ScrollController();
  int _prevPage = 1;
  double _opacity = 0.0;
  bool _disableBottom = false;
  PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();

    // _clearTimer = Timer.periodic(Duration(seconds: 1), (timer) {
    //   imageCache.clearLiveImages();
    //   imageCache.clear();
    // });

    Future.delayed(Duration(milliseconds: 100))
        .then((value) => _checkLatestRead());

    _scroll.addListener(() async {
      currentPage = offset2Page(_scroll.offset);
      if (_prevPage != currentPage) {
        if (currentPage > 0) {
          setState(() {
            _prevPage = currentPage;
          });
        }
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pageInfo = Provider.of<ViewerPageProvider>(context);
    _loaded = List<bool>.filled(_pageInfo.uris.length, false);
    _cachedHeight = List<double>.filled(_pageInfo.uris.length, -1);

    for (var url in _pageInfo.uris) {
      print(url);
    }

    print(_pageInfo.headers);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _clearTimer.cancel();
    PaintingBinding.instance.imageCache.clear();
    _pageInfo.uris.forEach((element) async {
      await CachedNetworkImageProvider(element).evict();
    });
    SystemChrome.setEnabledSystemUIOverlays([
      SystemUiOverlay.top,
      SystemUiOverlay.bottom,
    ]);
    imageCache.clearLiveImages();
    imageCache.clear();
    super.dispose();
  }

  void _checkLatestRead() {
    User.getInstance().then((value) => value.getUserLog().then((value) async {
          var x = value.where((e) => e.articleId() == _pageInfo.id.toString());
          if (x.length < 2) return;
          var e = x.elementAt(1);
          if (e.lastPage() == null) return;
          if (e.lastPage() > 1 &&
              DateTime.parse(e.datetimeStart())
                      .difference(DateTime.now())
                      .inDays <
                  7) {
            if (await Dialogs.yesnoDialog(
                context,
                Translations.of(context)
                    .trans('recordmessage')
                    .replaceAll('%s', e.lastPage().toString()),
                Translations.of(context).trans('record'))) {
              if (!Settings.isHorizontal) {
                _scroll.jumpTo(page2Offset(e.lastPage() - 1));
              } else {
                _pageController.jumpToPage(e.lastPage() - 1);
              }
            }
          }
        }));
  }

  int offset2Page(double offset) {
    double xx = -96;
    for (int i = 0; i < _cachedHeight.length; i++) {
      xx += _loaded[i] ? _cachedHeight[i] : 300;
      // xx += 4;
      if (offset < xx) {
        return i + 1;
      }
    }
    return _cachedHeight.length;
  }

  double page2Offset(int page) {
    double xx = 0.0;
    for (int i = 0; i < page; i++) {
      xx += _loaded[i] ? _cachedHeight[i] : 300;
    }
    return xx;
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
      sized: false,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        resizeToAvoidBottomPadding: false,
        appBar: _opacity == 1.0 ? _appBar() : null,
        body: Settings.isHorizontal ? _bodyHorizontal() : _bodyVertical(),
      ),
    );
  }

  _appBar() {
    return AppBar(
      elevation: 0.0,
      backgroundColor: Colors.black.withOpacity(0.3),
      title: Text('$_prevPage/${_pageInfo.uris.length}'),
      leading: IconButton(
        icon: new Icon(Icons.arrow_back),
        onPressed: () {
          Navigator.pop(context, currentPage);
          return new Future(() => false);
        },
      ),
      actions: [
        PopupMenuButton<_ViewAppBarAction>(
          onSelected: (action) {
            switch (action) {
              case _ViewAppBarAction.toggleViewer:
                // Navigator.pushNamed(context, SettingScreen.routeName);
                Settings.setIsHorizontal(!Settings.isHorizontal);
                if (Settings.isHorizontal) {
                  _pageController =
                      new PageController(initialPage: _prevPage - 1);
                } else {
                  Future.delayed(Duration(milliseconds: 100)).then((value) {
                    _scroll.jumpTo(page2Offset(_prevPage - 1) - 96);
                  });
                }
                setState(() {});
                break;

              case _ViewAppBarAction.toggleRightToLeft:
                // tryLaunch(client.getImageUrl(image.id));
                Settings.setRightToLeft(!Settings.rightToLeft);
                setState(() {});
                break;

              case _ViewAppBarAction.toggleScrollVertical:
                Settings.setScrollVertical(!Settings.scrollVertical);
                setState(() {});
                break;
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: _ViewAppBarAction.toggleViewer,
              child: Text('Toggle Viewer Style'),
            ),
            PopupMenuItem(
              value: _ViewAppBarAction.toggleRightToLeft,
              enabled: Settings.isHorizontal,
              child: Text('Toggle Right To Left'),
            ),
            PopupMenuItem(
              value: _ViewAppBarAction.toggleScrollVertical,
              enabled: Settings.isHorizontal,
              child: Text('Toggle Scroll Vertical'),
            ),
          ],
        ),
      ],
    );
  }

  _bodyVertical() {
    final height = MediaQuery.of(context).size.height;

    return Stack(
      children: <Widget>[
        PhotoView.customChild(
          minScale: 1.0,
          child: Container(
            color: const Color(0xff444444),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: _pageInfo.uris.length,
              controller: _scroll,
              cacheExtent: height * 2,
              itemBuilder: (context, index) {
                return _networkImageItem(index);
              },
            ),
          ),
        ),
        _touchArea(),
        !_disableBottom ? _bottomAppBar() : Container(),
      ],
    );
  }

  _bodyHorizontal() {
    return Stack(
      children: <Widget>[
        Container(
          decoration: const BoxDecoration(
            color: Colors.black,
          ),
          constraints: BoxConstraints.expand(
            height: MediaQuery.of(context).size.height,
          ),
          child: Stack(
            alignment: Alignment.bottomRight,
            children: <Widget>[
              PhotoViewGallery.builder(
                scrollPhysics: const BouncingScrollPhysics(),
                builder: _buildItem,
                itemCount: _pageInfo.uris.length,
                backgroundDecoration: const BoxDecoration(
                  color: Colors.black,
                ),
                pageController: _pageController,
                onPageChanged: (page) {
                  currentPage = page.toInt() + 1;
                  setState(() {
                    _prevPage = page.toInt() + 1;
                  });
                },
                scrollDirection:
                    Settings.scrollVertical ? Axis.vertical : Axis.horizontal,
                reverse: Settings.rightToLeft,
              ),
            ],
          ),
        ),
        _touchArea(),
        !_disableBottom ? _bottomAppBar() : Container(),
      ],
    );
  }

  PhotoViewGalleryPageOptions _buildItem(BuildContext context, int index) {
    return PhotoViewGalleryPageOptions(
      imageProvider: CachedNetworkImageProvider(
        _pageInfo.uris[index],
        headers: _pageInfo.headers,
      ),
      initialScale: PhotoViewComputedScale.contained,
      minScale: PhotoViewComputedScale.contained * 1.0,
      maxScale: PhotoViewComputedScale.contained * 5.0,
    );
  }

  bool _overlayOpend = false;
  _touchArea() {
    final height = MediaQuery.of(context).size.height;
    final width = MediaQuery.of(context).size.width;
    return Align(
      alignment: Alignment.center,
      child: Container(
        color: null,
        width: width / 3,
        height: height,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () async {
            if (!_overlayOpend) {
              if (!Settings.isHorizontal) _prevPage = currentPage;
              setState(() {
                _opacity = 1.0;
                _disableBottom = false;
              });
              SystemChrome.setEnabledSystemUIOverlays(
                  [SystemUiOverlay.bottom, SystemUiOverlay.top]);
            } else {
              setState(() {
                _opacity = 0.0;
              });
              SystemChrome.setEnabledSystemUIOverlays([]);
              Future.delayed(Duration(milliseconds: 300)).then((value) {
                setState(() {
                  _disableBottom = true;
                });
              });
            }
            _overlayOpend = !_overlayOpend;
          },
        ),
      ),
    );
  }

  _networkImageItem(index) {
    final width = MediaQuery.of(context).size.width;
    return FutureBuilder(
      future: _calculateImageDimension(_pageInfo.uris[index]),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          _loaded[index] = true;
          _cachedHeight[index] = width / snapshot.data.aspectRatio;
        }
        return CachedNetworkImage(
          imageUrl: _pageInfo.uris[index],
          httpHeaders: _pageInfo.headers,
          fit: BoxFit.cover,
          fadeInDuration: Duration(microseconds: 500),
          fadeInCurve: Curves.easeIn,
          // memCacheWidth: width.toInt(),
          progressIndicatorBuilder: (context, string, progress) {
            return SizedBox(
              height: 300,
              child: Center(
                child: SizedBox(
                  child: CircularProgressIndicator(value: progress.progress),
                  width: 30,
                  height: 30,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<Size> _calculateImageDimension(String url) async {
    Completer<Size> completer = Completer();
    Image image = new Image(
        image: CachedNetworkImageProvider(url, headers: _pageInfo.headers));
    image.image.resolve(ImageConfiguration()).addListener(
      ImageStreamListener(
        (ImageInfo image, bool synchronousCall) {
          var myImage = image.image;
          Size size = Size(myImage.width.toDouble(), myImage.height.toDouble());
          if (!completer.isCompleted) completer.complete(size);
        },
      ),
    );
    return completer.future;
  }

  _bottomAppBar() {
    final height = MediaQuery.of(context).size.height;
    final mediaQuery = MediaQuery.of(context);
    return AnimatedOpacity(
      opacity: _opacity,
      duration: Duration(milliseconds: 300),
      child: Padding(
        padding: EdgeInsets.only(
            top: height -
                (mediaQuery.padding + mediaQuery.viewInsets).bottom -
                (48)),
        child: Container(
          alignment: Alignment.bottomCenter,
          // padding: EdgeInsets.only(top: height - bottom - 48),
          color: Colors.black.withOpacity(0.2),
          height: 48,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Slider(
                value: _prevPage.toDouble() > 0 ? _prevPage.toDouble() : 1,
                max: _pageInfo.uris.length.toDouble(),
                min: 1,
                label: _prevPage.toString(),
                divisions: _pageInfo.uris.length,
                inactiveColor: Settings.majorColor.withOpacity(0.7),
                activeColor: Settings.majorColor,
                onChanged: (value) {
                  if (!Settings.isHorizontal) {
                    _scroll.jumpTo(page2Offset(_prevPage - 1) - 96);
                  } else {
                    _pageController.jumpToPage(value.toInt() - 1);
                  }
                  currentPage = value.toInt();
                  setState(() {
                    _prevPage = value.toInt();
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
