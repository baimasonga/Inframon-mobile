import 'package:sqflite/sqflite.dart';
  import 'package:path/path.dart';

  class DatabaseHelper {
    static final DatabaseHelper instance = DatabaseHelper._init();
    static Database? _database;

    DatabaseHelper._init();

    Future<Database> get database async {
      if (_database != null) return _database!;
      _database = await _initDB('inframon.db');
      return _database!;
    }

    Future<Database> _initDB(String filePath) async {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, filePath);

      return await openDatabase(
        path,
        version: 4,
        onCreate: _createDB,
        onUpgrade: _onUpgrade,
      );
    }

    Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
      if (oldVersion < 2) {
        await db.execute("""
        CREATE TABLE IF NOT EXISTS issues (
          id TEXT PRIMARY KEY,
          project_id TEXT,
          title TEXT,
          description TEXT,
          severity TEXT,
          status TEXT DEFAULT 'open',
          location_lat REAL,
          location_lng REAL,
          sync_status TEXT DEFAULT 'pending',
          created_at TEXT
        )
        """);
        await db.execute("""
        CREATE TABLE IF NOT EXISTS attendance_records (
          id TEXT PRIMARY KEY,
          project_id TEXT,
          inspector_id TEXT,
          check_in_time TEXT,
          check_out_time TEXT,
          total_hours REAL,
          gps_lat REAL,
          gps_lng REAL,
          verified_gps INTEGER DEFAULT 0,
          sync_status TEXT DEFAULT 'pending',
          created_at TEXT
        )
        """);
        await db.execute(
          'ALTER TABLE projects ADD COLUMN district TEXT',
        );
        await db.execute(
          'ALTER TABLE projects ADD COLUMN completion_percentage INTEGER DEFAULT 0',
        );
      }
      if (oldVersion < 3) {
        await db.execute('ALTER TABLE inspection_tasks ADD COLUMN field_notes TEXT');
        await db.execute('ALTER TABLE inspection_tasks ADD COLUMN gps_lat REAL');
        await db.execute('ALTER TABLE inspection_tasks ADD COLUMN gps_lng REAL');
        await db.execute('ALTER TABLE inspection_tasks ADD COLUMN updated_at TEXT');
        await db.execute("ALTER TABLE inspection_tasks ADD COLUMN sync_status TEXT DEFAULT 'synced'");
      }
      if (oldVersion < 4) {
        await db.execute("""
        CREATE TABLE IF NOT EXISTS inspection_photos (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          visit_id TEXT NOT NULL,
          local_path TEXT NOT NULL,
          remote_url TEXT,
          sync_status TEXT DEFAULT 'pending',
          created_at TEXT
        )
        """);
      }
    }

    Future _createDB(Database db, int version) async {
      await db.execute("""
      CREATE TABLE projects (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        status TEXT,
        district TEXT,
        completion_percentage INTEGER DEFAULT 0,
        created_at TEXT
      )
      """);

      await db.execute("""
      CREATE TABLE visit_metadata (
        id TEXT PRIMARY KEY,
        project_id TEXT,
        inspector_id TEXT,
        date_time TEXT,
        visit_type TEXT,
        weather_condition TEXT,
        site_supervisor_present INTEGER,
        overall_progress INTEGER,
        overall_status TEXT,
        recommendation TEXT,
        notes TEXT,
        gps_lat REAL,
        gps_lng REAL,
        sync_status TEXT DEFAULT 'pending'
      )
      """);

      await db.execute("""
      CREATE TABLE milestone_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        visit_id TEXT,
        milestone_name TEXT,
        status TEXT,
        completion_pct INTEGER,
        delay_days INTEGER,
        reason TEXT
      )
      """);

      await db.execute("""
      CREATE TABLE workforce_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        visit_id TEXT,
        role_category TEXT,
        count INTEGER,
        gender TEXT,
        is_youth INTEGER
      )
      """);

      await db.execute("""
      CREATE TABLE materials_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        visit_id TEXT,
        material_name TEXT,
        verification_status INTEGER,
        notes TEXT
      )
      """);

      await db.execute("""
      CREATE TABLE defect_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        visit_id TEXT,
        title TEXT,
        category TEXT,
        severity TEXT,
        action_plan TEXT,
        responsible_party TEXT,
        deadline TEXT
      )
      """);

      await db.execute("""
      CREATE TABLE issues (
        id TEXT PRIMARY KEY,
        project_id TEXT,
        title TEXT,
        description TEXT,
        severity TEXT,
        status TEXT DEFAULT 'open',
        location_lat REAL,
        location_lng REAL,
        sync_status TEXT DEFAULT 'pending',
        created_at TEXT
      )
      """);

      await db.execute("""
      CREATE TABLE attendance_records (
        id TEXT PRIMARY KEY,
        project_id TEXT,
        inspector_id TEXT,
        check_in_time TEXT,
        check_out_time TEXT,
        total_hours REAL,
        gps_lat REAL,
        gps_lng REAL,
        verified_gps INTEGER DEFAULT 0,
        sync_status TEXT DEFAULT 'pending',
        created_at TEXT
      )
      """);

      await db.execute("""
      CREATE TABLE user_profile (
        id TEXT PRIMARY KEY,
        full_name TEXT,
        role TEXT,
        assigned_districts TEXT,
        specializations TEXT
      )
      """);

      await db.execute("""
      CREATE TABLE project_assignments (
        id TEXT PRIMARY KEY,
        project_id TEXT,
        user_id TEXT,
        role_on_project TEXT
      )
      """);

      await db.execute("""
      CREATE TABLE inspection_tasks (
        id TEXT PRIMARY KEY,
        project_id TEXT,
        assignee_id TEXT,
        title TEXT,
        description TEXT,
        deadline TEXT,
        priority TEXT,
        status TEXT DEFAULT 'Pending',
        field_notes TEXT,
        gps_lat REAL,
        gps_lng REAL,
        updated_at TEXT,
        sync_status TEXT DEFAULT 'synced'
      )
      """);

      await db.execute("""
      CREATE TABLE inspection_photos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        visit_id TEXT NOT NULL,
        local_path TEXT NOT NULL,
        remote_url TEXT,
        sync_status TEXT DEFAULT 'pending',
        created_at TEXT
      )
      """);

      await db.execute("""
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
      """);
    }
  }
  