// Copyright 2016 Google Inc.
// Licensed under the Apache License, Version 2.0 (the 'License')
// You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqlite/sqlite.dart' as sqlite;
import 'package:test/test.dart';

Future<void> _createBlogTable(sqlite.Database db) async {
  await db.execute('CREATE TABLE posts (title text, body text)');
}

typedef Future<void> _DatabaseTest(sqlite.Database db);

Future<void> _runWithConnectionOnDisk(_DatabaseTest dbTest) async {
  final String fileName = path.join(
      Directory.systemTemp.createTempSync('dart-sqlite-test-').path,
      'db.sqlite');
  final sqlite.Database db = new sqlite.Database(fileName);
  return dbTest(db).whenComplete(() => db.close());
}

Future<void> _runWithConnectionInMemory(_DatabaseTest dbTest) async {
  final sqlite.Database db = new sqlite.Database.inMemory();
  return dbTest(db).whenComplete(() => db.close());
}

Function _testRunner(_DatabaseTest dbTest) {
  return () async {
    await _runWithConnectionOnDisk(dbTest);
    await _runWithConnectionInMemory(dbTest);
  };
}

void main() {
  test('query with bindings', _testRunner((sqlite.Database db) async {
    final sqlite.Row row = await db
        .query('SELECT ?+2, UPPER(?)', params: <dynamic>[3, 'hello']).first;
    expect(row[0], equals(5));
    expect(row[1], equals('HELLO'));
  }));

  test('query', _testRunner((sqlite.Database db) async {
    final sqlite.Row row = await db.query('SELECT 42 AS foo').first;
    expect(row.index, equals(0));
    expect(row[0], equals(42));
    expect(row['foo'], equals(42));
    expect(row.toList(), equals(const <int>[42]));
    expect(row.toMap(), equals(const <String, int>{'foo': 42}));
  }));

  test('query multiple', _testRunner((sqlite.Database db) async {
    await _createBlogTable(db);
    Future<void> insert(List<dynamic> bindings) async {
      final int inserted = await db.execute(
          'INSERT INTO posts (title, body) VALUES (?,?)',
          params: bindings);
      expect(inserted, equals(1));
    }

    await insert(<String>['hi', 'hello world']);
    await insert(<String>['bye', 'goodbye cruel world']);
    final List<sqlite.Row> rows =
        await db.query('SELECT * FROM posts').toList();
    expect(rows.length, equals(2));
    expect(rows[0]['title'], equals('hi'));
    expect(rows[1]['title'], equals('bye'));
    expect(rows[0].index, equals(0));
    expect(rows[1].index, equals(1));
  }));

  test('transaction success', _testRunner((sqlite.Database db) async {
    await _createBlogTable(db);
    await db.transaction(
        () => db.execute('INSERT INTO posts (title, body) VALUES (?,?)'));
    expect(await db.query('SELECT * FROM posts').length, equals(1));
  }));

  test('transaction failure', _testRunner((sqlite.Database db) async {
    return db
        .transaction(() => throw 'oh noes!')
        .catchError(expectAsync1<void, dynamic>((dynamic _) {}));
  }));

  test('syntax error', _testRunner((sqlite.Database db) async {
    expect(() => db.execute('random non sql'),
        throwsA(const TypeMatcher<sqlite.SqliteSyntaxException>()));
  }));

  test('column error', _testRunner((sqlite.Database db) async {
    final sqlite.Row row = await db.query('select 2+2').first;
    expect(() => row['qwerty'],
        throwsA(const TypeMatcher<sqlite.SqliteException>()));
  }));

  test('dynamic getters', _testRunner((sqlite.Database db) async {
    await _createBlogTable(db);
    final int inserted = await db
        .execute('INSERT INTO posts (title, body) VALUES ("hello", "world")');
    expect(inserted, equals(1));
    final List<sqlite.Row> rows =
        await db.query('SELECT * FROM posts').toList();
    expect(rows.length, equals(1));
    expect(rows[0]['title'], equals('hello'));
    expect(rows[0]['body'], equals('world'));
  }));
}
