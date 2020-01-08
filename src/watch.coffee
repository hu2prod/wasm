module = @
require "fy"
chokidar = require "chokidar"
{
  lib_compile
  mod_compile
} = require "./lib"

@watch = (opt, on_end)->
  {
    dir
    
    # mod_compile stuff
    path_c
    path_wasm
    path_wat
    
    obj_list
    # ---
    
    lib_dir_list
    init_compile
    chokidar_opt
    on_recompile_done
  } = opt
  
  obj_list          ?= []
  lib_dir_list      ?= []
  init_compile      ?= true
  chokidar_opt      ?= {}
  on_recompile_done ?= ()->
  
  norm_lib_dir_list = []
  do ()->
    for _lib in lib_dir_list
      _lib = {dir:_lib} if typeof _lib == "string"
      norm_lib_dir_list.push _lib
    return
  
  safe_on_recompile_done = ()->
    try
      on_recompile_done()
    catch err
      perr err
    
  
  if init_compile
    extra_obj_list = []
    is_ok = true
    await
      for lib in norm_lib_dir_list
        cb = defer()
        do (lib, cb)->
          await lib_compile lib, defer(err, res)
          if err
            perr err
            is_ok = false
          else
            extra_obj_list.append res.obj_list
          cb()
    
    if is_ok
      full_obj_list = obj_list.clone()
      full_obj_list.uappend extra_obj_list
      full_obj_list.sort()
      opt = {
        dir
        
        path_c
        path_wasm
        path_wat
        
        obj_list : full_obj_list
      }
      await mod_compile opt, defer(err)
      if err
        perr err
        is_ok = false
    
    safe_on_recompile_done() if is_ok
  
  recompile_in_progress = false
  recompile_handler = (file_change_hash, on_end)->
    # TODO check what lib/mod is this file related
    
    err = null
    is_ok = true
    extra_obj_list = []
    await
      for lib in norm_lib_dir_list
        is_needed = false
        for file,_v of file_change_hash
          if 0 == file.indexOf lib.dir
            is_needed = true
            break
        
        continue if !is_needed
        cb = defer()
        do (lib, cb)->
          await lib_compile lib, defer(err, res)
          if err
            perr err
            is_ok = false
          else
            extra_obj_list.append res.obj_list
          cb()
    
    if is_ok
      full_obj_list = obj_list.clone()
      full_obj_list.uappend extra_obj_list
      full_obj_list.sort()
      opt = {
        dir
        
        path_c
        path_wasm
        path_wat
        
        obj_list : full_obj_list
      }
      await mod_compile opt, defer(err)
      if err
        perr err
        is_ok = false
    
    on_end(err)
    safe_on_recompile_done() if is_ok
  
  # заимствовано с webcom
  first_update_ts = 0
  file_change_hash = {}
  update_delay_timer = null
  handler = (event, full_path)->
    # we didn't listen multiple directories
    # return if /^(\.git|test).*$/.test full_path
    
    is_wasm_path = false
    is_wasm_path = true if 0 == full_path.indexOf dir
    if !is_wasm_path
      for lib in norm_lib_dir_list
        if 0 == full_path.indexOf lib.dir
          is_wasm_path = true
          break
    
    if is_wasm_path
      return if /\.(o|o\.tmp|wasm|wasm.tmp.*|wat)$/.test full_path
      puts "[INFO] #{event.ljust 8} #{full_path}"
      if !recompile_in_progress
        first_update_ts = Date.now()
      
      file_change_hash[full_path] = true
      clearTimeout update_delay_timer if update_delay_timer?
      update_delay_timer = setTimeout ()->
        update_delay_timer = null
        if !recompile_in_progress
          recompile_in_progress = true
          scheduled_file_change_hash = file_change_hash
          file_change_hash = {}
          await recompile_handler scheduled_file_change_hash, defer(err)
          
          perr err if err
          recompile_in_progress = false
          esp_ts = Date.now() - first_update_ts
          status = if err then "FAIL" else "OK"
          puts "[INFO] update done #{status} in #{esp_ts} ms"
          # миникостыль для форсирования перекомпиляции если во время перекомпиляции произошли изменения
          if h_count file_change_hash
            handler "FORCED", Object.keys(file_change_hash)[0]
        
        return
      , 100 # because IDE/nfs can be not so fast
    # we didn't listen multiple directories and lot of crap
    # else
    #   puts "[INFO] #{event.ljust 8} #{full_path}"
    #   puts "Daemon files changed. Need restart"
    #   process.exit()
    return
  
  watcher = chokidar.watch dir, chokidar_opt
  for _lib in norm_lib_dir_list
    watcher.add _lib.dir
  watcher.on "unlink", (path)-> handler "unlink", path
  watcher.on "change", (path)-> handler "change", path
  
  is_ready = false
  on_ready = ()->
    return if is_ready
    is_ready = true
    puts "[INFO] watcher scan ready"
    watcher.on "add", (path)-> handler "add", path
    
    on_end null, {
      watcher
      handler
    }
    return
  
  timeout = null
  upd_ready_timer = ()->
    clearTimeout timeout if timeout?
    timeout = setTimeout on_ready, 5000 # Прим. это всего лишь recovery. chokidar в первую очередь должен попытаться решить это всё сам
    return
  
  watcher.on "add", (full_path)->
    upd_ready_timer()
  
  puts "[INFO] watcher start..."
  watcher.on "ready", on_ready
