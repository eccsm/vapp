import 'package:drift/drift.dart';

/// Represents the `categories` table.
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()(); // PRIMARY KEY AUTOINCREMENT
  TextColumn get name => text()();                 // NOT NULL
  IntColumn get color => integer()();              // NOT NULL
  TextColumn get icon => text().nullable()();      // NULL
}

/// Represents the `notes` table.
class Notes extends Table {
  IntColumn get id => integer().autoIncrement()(); // PRIMARY KEY AUTOINCREMENT

  TextColumn get title => text()();    // NOT NULL
  TextColumn get content => text()();  // NOT NULL
  TextColumn get audioPath => text().nullable()();

  /// Store timestamps as a DateTime in Drift.
  /// That way, you can pass `DateTime.now()` directly with no conversion needed.
  DateTimeColumn get createdAt => dateTime()();  // NOT NULL
  DateTimeColumn get updatedAt => dateTime()();  // NOT NULL

  /// `is_synced` is an integer 0 or 1 with a CHECK in raw SQL,
  /// but we can store it as a bool in Drift:
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();

  /// Foreign key to categories(id)
  IntColumn get categoryId => integer().nullable().references(Categories, #id)();
}

/// Represents the `tags` table.
class Tags extends Table {
  IntColumn get id => integer().autoIncrement()(); // PRIMARY KEY AUTOINCREMENT
  TextColumn get name => text().unique()();        // NOT NULL UNIQUE
}

/// Represents the `note_tags` relationship table.
class NoteTags extends Table {
  IntColumn get noteId => integer().references(Notes, #id)();
  IntColumn get tagId => integer().references(Tags, #id)();

  @override
  Set<Column> get primaryKey => {noteId, tagId};
}
