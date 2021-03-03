/*
c := {
  SQL:{
    DLL:{
      path:"/path/to/dll"
    },
    counter:0
  }
}

*/


class SQLite { ; 99% same as https://github.com/kczx3/SQLiteViewer/blob/master/lib/Class_SQLiteDB.ahk

  __New(DB:="") {
    global c
    This._Path := ""
    This._Handle := 0
    This._Queries := map()
    this.status := {}
    if (!c.sql.dll.HasOwnProp("handle") || !c.sql.dll.handle) {
      c.sql.dll.handle := DllCall("LoadLibrary", "Str", c.sql.dll.path, "UPtr")
    }
    ++c.sql.counter
    if (DB) {
      this.open(DB)
    }
  }
  
  __Delete() {
    if this._handle
      this.close()
    global c
    --c.sql.counter
    If (c.sql.dll.handle && c.sql.counter = 0) {
      DllCall("FreeLibrary", "Ptr", c.sql.dll.handle)
      c.sql.dll.handle := 0
    }
  }
  
  _ResetStatus() {
    this.status.Hint := ""
    this.status.ErrCode := 0
    this.status.ErrCodeX := 0
    this.status.ErrStr := ""
    this.status.ErrMsg := ""
    this.status.exception := ""
  }
  
  Class _Table {
    
    __New() {
      This.ColumnCount := 0
      This.RowCount := 0
      This.ColumnNames := []
      This.Rows := []
      This.HasNames := False
      This.HasRows := False
      This._CurrentRow := 0
    }
    
    GetRow(RowIndex, ByRef Row) {
      Row := ""
      If (RowIndex < 1 || RowIndex > This.RowCount)
        Return False
      If !This.Rows.Has(RowIndex)
        Return False
      Row := This.Rows[RowIndex]
      This._CurrentRow := RowIndex
      Return True
    }
    
    Next(ByRef Row) {
      Row := ""
      If (This._CurrentRow >= This.RowCount)
        Return -1
      This._CurrentRow += 1
      If !This.Rows.Has(This._CurrentRow)
        Return False
      Row := This.Rows[This._CurrentRow]
      Return True
    }
    
    Reset() {
      This._CurrentRow := 0
      Return True
    }
  }
  
  Open(path:="") {
    This._ResetStatus()
    handle := 0
    If (!path)
       path := ":memory:"
    If (path = This._Path) && (This._Handle)
       Return True
    If (This._Handle) {
       This.status.hint := "You must first close DB " . This._Path . "!"
       Return False
    }
    This._Path := path
    try {
      ; int sqlite3_open16(
      ;   const void *filename,   /* Database filename (UTF-16) */
      ;   sqlite3 **ppDb          /* OUT: SQLite db handle */
      ; );
      
      RC := DllCall("SQlite3.dll\sqlite3_open16"
      , "Ptr", StrPtr(path)
      , "PtrP", handle
      , "Cdecl Int")
    } catch e {
      this.status.hint := "could not connect to " path
      this.status.exception := e
      return false
    }
    If (RC) {
       This._Path := ""
       This.status.hint := This._ErrMsg()
       This.status.code := RC
       Return False
    }
    This._Handle := handle
    Return True
  }
  
  Close() {
    this._resetstatus()
    This.SQL := ""
    If !(This._Handle)
      Return True
    For ,Query in This._Queries
      ; int sqlite3_finalize(sqlite3_stmt *pStmt);
      DllCall("SQlite3.dll\sqlite3_finalize", "Ptr", Query, "Cdecl Int")
    try { ; int sqlite3_close(sqlite3*);
      RC := DllCall("SQlite3.dll\sqlite3_close", "Ptr", This._Handle, "Cdecl Int")
    } catch e {
      This.status.hint := "DLLCall sqlite3_close failed!"
      this.status.exception := e
      Return False
    }
    If (RC) {
      This.status.errmsg := This._ErrMsg()
      This.status.errcode := RC
      Return False
    }
    This._Path := ""
    This._Handle := ""
    This._Queries := []
    Return True
  }
  
  Exec(SQL, Callback := "") {
    this._resetstatus()
    This.SQL := SQL
    If !(This._Handle) {
      This.this.hint := "Invalid dadabase handle!"
      Return False
    }
    CBPtr := 0
    Err := 0
    If (Type(Callback) = "Func" && (Callback.MinParams = 4))
      CBPtr := CallbackCreate(Callback, "FC", 4)
    ObjAddRef(address := ObjPtr(this))
    try {
      ; int sqlite3_exec(
      ;   sqlite3*,                                  /* An open database */
      ;   const char *sql,                           /* SQL to be evaluated */
      ;   int (*callback)(void*,int,char**,char**),  /* Callback function */
      ;   void *,                                    /* 1st argument to callback */
      ;   char **errmsg                              /* Error msg written here */
      ; );
      
      RC := DllCall("SQlite3.dll\sqlite3_exec"
      , "Ptr", This._Handle
      , "Ptr", StrBuf(SQL).Ptr
      , "Ptr", CBPtr
      , "Ptr", address
      , "PtrP", Err
      , "Cdecl Int")
    } catch e {
      this.status.exception := e
    }
    ObjRelease(address)
    
    If (CBPtr)
      CallbackFree(CBPtr)
    If (this.status.exception) {
      This.status.hint := "DLLCall sqlite3_exec failed!"
      Return False
    }
    If (RC) {
      This.status.errmsg := Err ? StrGet(Err, "UTF-8") : ""
      This.status.errcode := RC
      ; void sqlite3_free(void*);
      DllCall("SQLite3.dll\sqlite3_free", "Ptr", Err, "Cdecl")
      Return False
    }
    This.Changes := This._Changes()
    Return True
  }
  
  GetTable(SQL, ByRef TB, MaxResult := 0) {
    this._resetstatus()
    TB := ""
    This.SQL := SQL
    If !(This._Handle) {
      This.status.hint := "Invalid dadabase handle!"
      Return False
    }
    If !RegExMatch(SQL, "i)^\s*(SELECT|PRAGMA)\s") {
      This.status.hint := "Method " . A_ThisFunc . " requires a query statement!"
      Return False
    }
    Names := ""
    Err := 0, RC := 0, GetRows := 0
    I := 0, Rows := Cols := 0
    Table := 0
    If (Type(MaxResult) != "Integer")
      MaxResult := 0
    If (MaxResult < -2)
      MaxResult := 0
    try {
      
      ; int sqlite3_get_table(
      ;   sqlite3 *db,          /* An open database */
      ;   const char *zSql,     /* SQL to be evaluated */
      ;   char ***pazResult,    /* Results of the query */
      ;   int *pnRow,           /* Number of result rows written here */
      ;   int *pnColumn,        /* Number of result columns written here */
      ;   char **pzErrmsg       /* Error msg written here */
      ; );
      
      RC := DllCall("SQlite3.dll\sqlite3_get_table"
      , "Ptr", This._Handle
      , "Ptr", StrBuf(SQL).Ptr
      , "PtrP", Table
      , "IntP", Rows
      , "IntP", Cols
      , "PtrP", Err
      , "Cdecl Int")
      
    } catch e {
      This.status.hint := "DLLCall sqlite3_get_table failed!"
      This.status.exception := e
      Return False
    }
    If (RC) {
      This.status.hint := StrGet(Err, "UTF-8")
      This.status.errcode := RC
      DllCall("SQLite3.dll\sqlite3_free", "Ptr", Err, "Cdecl")
      Return False
    }
    TB := SQLite._Table.new()
    TB.ColumnCount := Cols
    TB.RowCount := Rows
    If (MaxResult = -1) {
      try {
        ; void sqlite3_free_table(char **result);
        DllCall("SQLite3.dll\sqlite3_free_table", "Ptr", Table, "Cdecl")
      } catch e {
        This.status.hint := "DLLCall sqlite3_free_table failed!"
        This.status.exception := e
        Return False
      }
      Return True
    }
    If (MaxResult = -2)
      GetRows := 0
    Else If (MaxResult > 0) && (MaxResult <= Rows)
      GetRows := MaxResult
    Else
      GetRows := Rows
    Offset := 0
    Names := Array()
    Loop(Cols) {
      Names.push(StrGet(NumGet(Table+0, Offset, "UPtr"), "UTF-8"))
      Offset += A_PtrSize
    }
    TB.ColumnNames := Names
    TB.HasNames := True
    Loop(GetRows) {
      TB.Rows.push([])
      Loop(Cols) {
        address := NumGet(Table+0, Offset, "UPtr")
        TB.Rows[-1].push(address ? StrGet(address, "UTF-8") : "")
        Offset += A_PtrSize
      }
    }
    If (GetRows)
      TB.HasRows := True
    try {
      DllCall("SQLite3.dll\sqlite3_free_table", "Ptr", Table, "Cdecl")
    } catch e {
      TB := ""
      This.status.hint := "DLLCall sqlite3_free_table failed!"
      This.status.errcode := e
      Return False
    }
    Return True
  }
  
  
  ; #######################################################
  ; wrappers for https://www.sqlite.org/c3ref/funclist.html
  ; #######################################################
  
  
  _BusyHandler() { ; int sqlite3_busy_handler(sqlite3*,int(*)(void*,int),void*);
    
  }
  
  _BusyTimeout(x:=5000) { ; int sqlite3_busy_timeout(sqlite3*, int ms);
    Return DllCall("SQLite3.dll\sqlite3_busy_timeout", "Ptr", This._Handle, "Int", x, "Cdecl Int")
  }
  
  _Changes() { ; int sqlite3_changes(sqlite3*);
    Return DllCall("SQLite3.dll\sqlite3_changes", "Ptr", This._Handle, "Cdecl Int")
  }
  
  _TotalChanges() { ; int sqlite3_total_changes(sqlite3*);
    Return DllCall("SQLite3.dll\sqlite3_total_changes", "Ptr", This._Handle, "Cdecl Int")
  }
  
  _ClearBindings() { ; int sqlite3_clear_bindings(sqlite3_stmt*);
    
  }
  
  _Close() { ; int sqlite3_close_v2(sqlite3*);
    return DllCall("SQLite3.dll\sqlite3_close_v2", "Ptr", This._Handle, "Cdecl Int")
  }
  
  _CollationNeeded() {
    ; int sqlite3_collation_needed16(
    ;   sqlite3*,
    ;   void*,
    ;   void(*)(void*,sqlite3*,int eTextRep,const void*)
    ; );
    
    ;return DllCall("SQLite3.dll\sqlite3_collation_needed16", "Ptr", This._Handle,x,x,x,x "Cdecl Int")
  }
  
  _ErrCode() { ; int sqlite3_errcode(sqlite3 *db);
    return DllCall("SQLite3.dll\sqlite3_errcode", "Ptr", This._Handle, "Cdecl Int")
  }
  
  _ErrStr(RC:="") { ; const char *sqlite3_errstr(int);
    if (!RC && RC != 0) {
      RC := this.status.errcode
    }
    ;try {
      return StrGet(DllCall("SQLite3.dll\sqlite3_errstr", "Int", RC, "Cdecl UPtr"),"UTF-8")
    ;}
  }
  
  _ExtErrCode() { ; int sqlite3_extended_errcode(sqlite3 *db);
    return DllCall("SQLite3.dll\sqlite3_extended_errcode", "Ptr", This._Handle, "Cdecl Int")
  }
  
  _ErrMsg() { ; const void *sqlite3_errmsg16(sqlite3*);
    try {
      return StrGet(DllCall("SQLite3.dll\sqlite3_errmsg16", "Ptr", This._Handle, "Cdecl UPtr"))
    }
  }
  
  _Exec() {
    ; int sqlite3_exec(
    ;   sqlite3*,                                  /* An open database */
    ;   const char *sql,                           /* SQL to be evaluated */
    ;   int (*callback)(void*,int,char**,char**),  /* Callback function */
    ;   void *,                                    /* 1st argument to callback */
    ;   char **errmsg                              /* Error msg written here */
    ; );
  }
  
  _LastInsertRowID() { ; sqlite3_int64 sqlite3_last_insert_rowid(sqlite3*);
    return DllCall("SQLite3.dll\sqlite3_last_insert_rowid", "Ptr", This._Handle, "Cdecl Int64")
  }
  
  _Prepare() {
    ; int sqlite3_prepare16_v3(
    ;   sqlite3 *db,            /* Database handle */
    ;   const void *zSql,       /* SQL statement, UTF-16 encoded */
    ;   int nByte,              /* Maximum length of zSql in bytes. */
    ;   unsigned int prepFlags, /* Zero or more SQLITE_PREPARE_ flags */
    ;   sqlite3_stmt **ppStmt,  /* OUT: Statement handle */
    ;   const void **pzTail     /* OUT: Pointer to unused portion of zSql */
    ; );
    
    DllCall("SQLite3.dll\sqlite3_prepare16_v3"
    , "Ptr", This._Handle, "Cdecl UPtr")
  }
  
}
