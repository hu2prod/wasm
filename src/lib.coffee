module = @
require "fy"
require "lock_mixin"
fs      = require "fs"
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
      job_list.push {cmd, dir}
      obj_list.upush "#{dir}/build/#{file_o}"
  
  if opt.seq
    await on_end = lock opt, on_end, defer()
    for job in job_list
      {cmd, dir} = job
      await exec cmd, {cwd: dir}, defer(err); return on_end err if err
  else
    for job in job_list
      await limiter.lock defer()
      do (job)->
        {cmd, dir} = job
        await exec cmd, {cwd: dir}, defer(err); return on_end err if err
        limiter.unlock()
    await limiter.drain defer()
  
  # just to keep stable
  obj_list.sort()
  
  on_end null, {obj_list}

@mod_compile = (opt, on_end)->
  {
    # если не заполнять dir, то нужно заполнить все 3 остальных параметра
    dir
    
    path_c
    path_wasm
    path_wat
    
    obj_list
  } = opt
  if dir
    path_c    ?= "#{dir}/index.c"
    path_wasm ?= "#{dir}/index.wasm"
    path_wat  ?= "#{dir}/index.wat"
  
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
  
  cmd = "clang-8 #{flag_list.join ' '} -std=c11 -o #{path_wasm} #{path_c} #{opt.obj_list.join ' '}"
  await exec cmd, defer(err); return on_end err if err
  
  await fs.readFile path_wasm, defer(err, wasm_buffer); return on_end err if err
  
  setTimeout ()->
    # dev life quality
    wat_buffer = wabt.readWasm(wasm_buffer, {}).toText({})
    await fs.writeFile path_wat, wat_buffer, defer(err);
    perr err if err
  , 0
  
  on_end()

