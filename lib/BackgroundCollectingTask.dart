import 'dart:convert';
// import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:scoped_model/scoped_model.dart';

// import 'storage.dart';

import 'dart:async';
import 'dart:io';

int fileCounter = 0;

Future<String> get _localPath async {
  // var directory = await Directory('/logs').create(recursive: true);
  // return directory.path;
  return "/storage/emulated/0/Documents";
}

Future<File> get _localFile async {
  final path = await _localPath;
  // fileCounter += 1;
  return File('$path/$fileCounter.txt');
}

Future<File> writeData(double data) async {
  final file = await _localFile;

  // Write the file
  return file.writeAsString('$data\n', mode: FileMode.append);
}

class DataSample {
  double ecgData;
  DateTime timestamp;

  DataSample({
    required this.ecgData,
    required this.timestamp,
  });
}

class BackgroundCollectingTask extends Model {
  static BackgroundCollectingTask of(
    BuildContext context, {
    bool rebuildOnChange = false,
  }) =>
      ScopedModel.of<BackgroundCollectingTask>(
        context,
        rebuildOnChange: rebuildOnChange,
      );

  final BluetoothConnection _connection;

  List<int> _buffer = List<int>.empty(growable: true);

  List<DataSample> samples = List<DataSample>.empty(growable: true);

  bool inProgress = false;

  BackgroundCollectingTask._fromConnection(this._connection) {
    _connection.input!.listen((data) {
      _buffer += data;
      var gain = 1.00;
      while (true) {
        int index = 0;
        final DataSample sample = DataSample(
            ecgData: (_buffer[index] * gain), timestamp: DateTime.now());
        _buffer.removeAt(index);
        samples.add(sample);
        notifyListeners();
        double ecgdata = sample.ecgData;
        writeData(ecgdata);
      }
    }).onDone(() {
      inProgress = false;
      notifyListeners();
    });
  }

  static Future<BackgroundCollectingTask> connect(
      BluetoothDevice server) async {
    final BluetoothConnection connection =
        await BluetoothConnection.toAddress(server.address);
    fileCounter += 1;
    return BackgroundCollectingTask._fromConnection(connection);
  }

  void dispose() {
    _connection.dispose();
  }

  Future<void> start() async {
    inProgress = true;
    _buffer.clear();
    samples.clear();
    notifyListeners();
    _connection.output.add(ascii.encode('start'));
    await _connection.output.allSent;
  }

  Future<void> cancel() async {
    inProgress = false;
    notifyListeners();
    _connection.output.add(ascii.encode('stop'));
    await _connection.finish();
  }

  Future<void> pause() async {
    inProgress = false;
    notifyListeners();
    _connection.output.add(ascii.encode('stop'));
    await _connection.output.allSent;
  }

  Future<void> reasume() async {
    inProgress = true;
    notifyListeners();
    _connection.output.add(ascii.encode('start'));
    await _connection.output.allSent;
  }

  Iterable<DataSample> getLastOf(Duration duration) {
    DateTime startingTime = DateTime.now().subtract(duration);
    int i = samples.length;
    do {
      i -= 1;
      if (i <= 0) {
        break;
      }
    } while (samples[i].timestamp.isAfter(startingTime));
    return samples.getRange(i, samples.length);
  }
}
