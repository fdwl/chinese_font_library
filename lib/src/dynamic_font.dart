import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

enum _FontSource { asset, file, url }

class DynamicFont {
  final String fontFamily;
  final String uri;
  final _FontSource _source;

  /// Use the font from AssetBundle, [key] is the same as in [rootBundle.load]
  DynamicFont.asset({required this.fontFamily, required String key})
      : _source = _FontSource.asset,
        uri = key;

  /// Use the font from [filepath]
  DynamicFont.file({required this.fontFamily, required String filepath})
      : _source = _FontSource.file,
        uri = filepath;

  bool? overwrite;

  /// Download the font, save to the device, then use it when needed
  DynamicFont.url(
      {required this.fontFamily, required String url, this.overwrite})
      : _source = _FontSource.url,
        uri = url;

  //debug
  bool testLoaded() {
    final customFont = TextPainter(
      text: TextSpan(
        text: 'Hello, Flutter!',
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: 24,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    return customFont.size.width > 0 && customFont.size.height > 0;
  }

  //文件是否已经下载, 仅对网络URL有效
  Future<bool> isDownloaded() async {
    if (_source != _FontSource.url) return false;

    final dir = (await getApplicationSupportDirectory()).path;
    final filename = Uri.parse(uri).pathSegments.last;
    final file = File('$dir/$filename');
    return await file.exists();
  }

  Future<bool> load({void Function(double progress)? downloadProgress}) async {
    switch (_source) {
      case _FontSource.asset:
        try {
          final loader = FontLoader(fontFamily);
          final fontData = rootBundle.load(uri);
          loader.addFont(fontData);
          await loader.load();
          return true;
        } catch (e) {
          debugPrint("Font asset error!!!");
          debugPrint(e.toString());
          return false;
        }
      case _FontSource.file:
        if (!await File(uri).exists()) return false;
        try {
          await loadFontFromList(
            await File(uri).readAsBytes(),
            fontFamily: fontFamily,
          );
          return true;
        } catch (e) {
          debugPrint("Font file error!!!");
          debugPrint(e.toString());
          return false;
        }
      case _FontSource.url:
        try {
          await loadFontFromList(
            await downloadFont(uri,
                overwrite: overwrite ?? false,
                downloadProgress: downloadProgress),
            fontFamily: fontFamily,
          );
          return true;
        } catch (e, s) {
          debugPrint("Font download failed!!!");
          debugPrint(e.toString());
          debugPrint(s.toString());
          return false;
        }
    }
  }
}

Future<Uint8List> downloadFont(String url,
    {bool overwrite = false,
    void Function(double progress)? downloadProgress}) async {
  final uri = Uri.parse(url);
  final filename = uri.pathSegments.last;
  final dir = (await getApplicationSupportDirectory()).path;
  final file = File('$dir/$filename');

  if (await file.exists() && !overwrite) {
    return await file.readAsBytes();
  }

  final bytes = await downloadBytes(uri, downloadProgress: downloadProgress);
  file.writeAsBytes(bytes);
  return bytes;
}

Future<void> downloadFontTo(String url,
    {required String filepath, bool overwrite = false}) async {
  final uri = Uri.parse(url);
  final file = File(filepath);

  if (await file.exists() && !overwrite) return;
  await file.writeAsBytes(await downloadBytes(uri));
}

Future<Uint8List> downloadBytes(Uri uri,
    {void Function(double progress)? downloadProgress}) async {
  final client = http.Client();
  final request = http.Request('GET', uri);
  final response =
      await client.send(request).timeout(const Duration(seconds: 5));

  if (response.statusCode != 200) {
    throw HttpException("status code ${response.statusCode}");
  }

  List<int> bytes = [];
  double prevPercent = 0;
  await response.stream.listen((List<int> chunk) {
    bytes.addAll(chunk);

    if (response.contentLength == null) {
      debugPrint('download font: ${bytes.length} bytes');
    } else {
      final progress = bytes.length / response.contentLength!;
      if (progress - prevPercent > 0.1 || progress > 0.99) {
        downloadProgress?.call(progress);
        prevPercent = progress;
      }
      // final percent = ((bytes.length / response.contentLength!) * 100);
      // if (percent - prevPercent > 15 || percent > 99) {
      //   debugPrint('download font: ${percent.toStringAsFixed(1)}%');
      //   prevPercent = percent;
      // }
    }
  }).asFuture();

  return Uint8List.fromList(bytes);
}
