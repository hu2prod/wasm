module = @
require "fy"
require "lock_mixin"
fs      = require "fs"
mod_path= require "path"
wabt    = require("wabt")()
{
  exec
  execSync
} = require "child_process"

@limiter = limiter = new Lock_mixin
# thread trashing (Пока остановится, пока нас уведомит, другие уже успеют захватить ресурсы и выполнится)
# потому thread'ов можно в 2 раза больше (даже поверх hyper threading'а)
limiter.$limit = 2*+execSync "cat /proc/cpuinfo  | grep 'model name' | wc -l"

lock = (opt, wrap_me, continue_fn)->
  if opt.seq
    continue_fn()
  else
    limiter.lock continue_fn
  (err, res)->
    limiter.unlock() if !opt.seq
    wrap_me err, res

@readdir = (dir)->
  list = fs.readdirSync dir
  list.sort()
  list

@lib_compile = (opt, on_end)->
  {
    dir
    verbose
  } = opt
  
  flag_list = [
    "-c" # .o file
    "--target=wasm32"
    "-O3"
    "-flto"
    "-nostdlib"
    "-Wl,--no-entry"
    "-Wl,--export-all"
    "-Wl,--lto-O3"
  ]
  if opt.drop_clang_warning
    flag_list.push "-w"
  
  await exec "mkdir -p #{dir}/build", defer(err); return on_end err if err
  
  obj_list = []
  job_list = []
  for file in module.readdir dir
    full_file = "#{dir}/#{file}"
    stat = fs.lstatSync full_file
    continue if stat.isDirectory()
    if /\.c$/.test full_file
      # buildable
      file_o  = file.replace /\.c$/, ".o"
      cmd = "clang-8 #{flag_list.join ' '} -o ./build/#{file_o} ./#{file}"
      # p cmd # DEBUG
      job_list.push {cmd, dir, file}
      obj_list.upush "#{dir}/build/#{file_o}"
  
  if opt.seq
    await on_end = lock opt, on_end, defer()
    for job in job_list
      {cmd, dir, file} = job
      await exec cmd, {cwd: dir}, defer(err, stdout, stderr)
      if err
        perr "####################################################################################################"
        perr "failed to build #{dir}"
        perr stderr
        return on_end err
      
      if verbose
        puts "#{dir}/#{file}"
  else
    first_err = null
    for job in job_list
      await limiter.lock defer()
      do (job)->
        {cmd, dir} = job
        # can't use file here because file is shared variable
        await exec cmd, {cwd: dir}, defer(err, stdout, stderr)
        if err
          perr "####################################################################################################"
          perr "failed to build #{dir}"
          perr stderr
        
        first_err ?= err # prevent limiter dead-lock
        if verbose
          puts "#{dir}/#{job.file}"
        limiter.unlock()
    await limiter.drain defer()
    return on_end first_err if first_err
  
  # just to keep stable
  obj_list.sort()
  
  on_end null, {obj_list}

_mod_compile_counter = 0
@mod_compile = (opt, on_end)->
  {
    # если не заполнять dir, то нужно заполнить все 3 остальных параметра
    dir
    
    use_wasm_runtime
    path_proxy
    path_c
    path_wasm
    path_wat
    
    obj_list
    verbose
    keep_tmp
  } = opt
  if dir
    path_c    ?= "#{dir}/index.c"
    path_wasm ?= "#{dir}/index.wasm"
    path_wat  ?= "#{dir}/index.wat"
  
  use_wasm_runtime ?= true
  path_proxy ?= "/tmp/#{process.pid}_#{_mod_compile_counter++}.c"
  
  return on_end new Error "missing path_c"    if !path_c
  return on_end new Error "missing path_wasm" if !path_wasm
  # optional. If missing will not generate at all
  # return on_end new Error "missing path_wat"  if !path_wat
  return on_end new Error "missing obj_list"  if !obj_list
  
  await on_end = lock opt, on_end, defer()
  
  flag_list = [
    "--target=wasm32"
    "-O3"
    "-flto"
    "-nostdlib"
    "-Wl,--no-entry"
    "-Wl,--export-dynamic"
    "-Wl,-z,stack-size=#{8 * 1024 * 1024}"
    "-Wl,--lto-O3"
  ]
  if opt.drop_clang_warning
    flag_list.push "-w"
  if use_wasm_runtime
    flag_list.push "-I#{mod_path.resolve 'node_modules/wasm_runtime/lib'}"
  
  compile_target = path_c
  
  # if !use_wasm_runtime
  #   compile_target = path_c
  # else
  #   compile_target = path_proxy
  #   runtime_path = "node_modules/wasm_runtime/lib/runtime.h"
  #   proxy_cont = """
  #   #include #{JSON.stringify mod_path.resolve runtime_path}
  #   #include #{JSON.stringify mod_path.resolve path_c}
  #   
  #   """
  #   
  #   await fs.writeFile path_proxy, proxy_cont, defer(err); return on_end err if err
  #   
  #   old_on_end = on_end
  #   on_end = ()->
  #     unless keep_tmp
  #       await fs.unlink path_proxy, defer(err); return old_on_end err if err
  #     old_on_end()
  
  cmd = "clang-8 #{flag_list.join ' '} -std=c11 -o #{path_wasm} #{compile_target} #{opt.obj_list.join ' '}"
  await exec cmd, defer(err, stdout, stderr)
  if err
    perr "####################################################################################################"
    perr "failed to build #{dir}"
    perr stderr
    return on_end err
  if verbose
    puts dir
  
  await fs.readFile path_wasm, defer(err, wasm_buffer); return on_end err if err
  
  setTimeout ()->
    # dev life quality
    wat_buffer = wabt.readWasm(wasm_buffer, {}).toText({})
    await fs.writeFile path_wat, wat_buffer, defer(err);
    perr err if err
  , 0
  
  on_end()

