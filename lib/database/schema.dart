import 'package:drift/drift.dart';

/// Executes the SQL to create all tables for schema version 1.
Future<void> createV1(Migrator m) async {
  // Create categories table
  await m.create('''
    CREATE TABLE IF NOT EXISTS "categories" (
      "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, 
      "name" TEXT NOT NULL, 
      "color" INTEGER NOT NULL, 
      "icon" TEXT NULL
    )
  ''' as DatabaseSchemaEntity);

  // Create notes table
  await m.create('''
    CREATE TABLE IF NOT EXISTS "notes" (
      "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, 
      "title" TEXT NOT NULL, 
      "content" TEXT NOT NULL, 
      "audio_path" TEXT NULL, 
      "created_at" INTEGER NOT NULL, 
      "updated_at" INTEGER NOT NULL, 
      "is_synced" INTEGER NOT NULL DEFAULT 0 CHECK ("is_synced" IN (0, 1)), 
      "category_id" INTEGER NULL REFERENCES categories (id)
    )
  ''' as DatabaseSchemaEntity);

  // Create tags table
  await m.create('''
    CREATE TABLE IF NOT EXISTS "tags" (
      "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, 
      "name" TEXT NOT NULL UNIQUE
    )
  ''' as DatabaseSchemaEntity);

  // Create note_tags table
  await m.create('''
    CREATE TABLE IF NOT EXISTS "note_tags" (
      "note_id" INTEGER NOT NULL REFERENCES notes (id), 
      "tag_id" INTEGER NOT NULL REFERENCES tags (id), 
      PRIMARY KEY ("note_id", "tag_id")
    )
  ''' as DatabaseSchemaEntity);
}

/// Validates that the current database schema matches what we expect.
Future<void> validateDatabaseSchema(QueryExecutor executor) async {
  // You can add validation logic here if needed
  // This is typically used to verify the schema in production
}