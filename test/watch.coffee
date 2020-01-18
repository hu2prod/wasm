# сначала должен выполниться этот набор тестов
require "./lib" 

assert = require "assert"
fs = require "fs"
# mod = require "../src/lib"
mod = require "../src/index"
# but test only watch part

{execSync} = require "child_process"
json_eq = (a, b)->
  assert.strictEqual JSON.stringify(a, null, 2), JSON.stringify(b, null, 2)

# 2>/dev/null suppresses stderr
#  ; echo -n '' suppresses error code 1

retry_cb_wait_time = 500
retry_cb = (cb, on_end)->
  err = null
  for i in [0 ... retry_cb_wait_time/100]
    await setTimeout defer(), 100
    try
      cb()
      return on_end()
    catch err
      'skip'
  
  on_end err


describe "watch section", ()->
  event_counter = 0
  watcher = null
  it "start watch", (on_end)->
    @timeout 10000
    execSync "rm wasm_test/lib/build/*.o  2>/dev/null ; echo -n ''"
    execSync "rm wasm_test/lib/extra.h    2>/dev/null ; echo -n ''"
    
    execSync "rm wasm_test/mod/index.wasm 2>/dev/null ; echo -n ''"
    execSync "rm wasm_test/mod/index.wat  2>/dev/null ; echo -n ''"
    execSync "rm wasm_test/mod/extra.h    2>/dev/null ; echo -n ''"
    
    opt = {
      dir : "wasm_test/mod"
      lib_dir_list : ["wasm_test/lib"]
      on_recompile_done : ()->
        p "on_recompile_done EXT"
        event_counter++
      use_wasm_runtime : false
    }
    
    await mod.watch opt, defer(err, res); return on_end err if err
    watcher = res.watcher
    on_end()
  
  it "init_compile", ()->
    # init_compile
    assert.strictEqual event_counter, 1
  
  it "init_compile", (on_end)->
    assert_value = event_counter + 1
    fs.writeFileSync "wasm_test/mod/extra.c", ""
    retry_cb ()->
      assert.strictEqual event_counter, assert_value
    , on_end
  
  it "add mod/extra.c", (on_end)->
    assert_value = event_counter + 1
    fs.writeFileSync "wasm_test/mod/extra.c", ""
    retry_cb ()->
      assert.strictEqual event_counter, assert_value
    , on_end
  
  it "remove mod/extra.c", (on_end)->
    assert_value = event_counter + 1
    fs.unlinkSync "wasm_test/mod/extra.c"
    retry_cb ()->
      assert.strictEqual event_counter, assert_value
    , on_end
  
  it "add lib/extra.h", (on_end)->
    assert_value = event_counter + 1
    fs.writeFileSync "wasm_test/lib/extra.h", ""
    retry_cb ()->
      assert.strictEqual event_counter, assert_value
    , on_end
  
  it "remove lib/extra.h", (on_end)->
    assert_value = event_counter + 1
    fs.unlinkSync "wasm_test/lib/extra.h"
    retry_cb ()->
      assert.strictEqual event_counter, assert_value
    , on_end
  
  it "fast change should trigger 1 recompile (can fail)", (on_end)->
    @timeout 20000
    err = null
    for retry_i in [0 ... 10]
      assert_value = event_counter + 1
      fs.writeFileSync "wasm_test/lib/extra.h", ""
      await setTimeout defer(), 10 # we must return control to watcher for a bit
      fs.unlinkSync "wasm_test/lib/extra.h"
      await setTimeout defer(), 500
      try
        assert.strictEqual event_counter, assert_value
        break
      catch err
        "skip"
      
      await setTimeout defer(), 500
      puts "retry #{retry_i}"
    on_end(err)
  
  it "stop watch", (on_end)->
    await watcher.close().then defer()
    # close is async, and also ... didn't stop before promise fire (a little bit later)... LOL
    await setTimeout defer(), 1000 # WTF???
    
    on_end()
  
  it "change after stop should not affect anything", (on_end)->
    assert_value = event_counter
    fs.writeFileSync "wasm_test/lib/extra.h", ""
    await setTimeout defer(), 10 # we must return control to watcher for a bit
    fs.unlinkSync "wasm_test/lib/extra.h"
    await setTimeout defer(), 500
    assert.strictEqual event_counter, assert_value
    on_end()
  
  it "no init_compile", (on_end)->
    event_counter = 0
    opt = {
      dir : "wasm_test/mod"
      lib_dir_list: ["wasm_test/lib"]
      init_compile: false
      on_recompile_done : ()->
        p "on_recompile_done EXT"
        event_counter++
      use_wasm_runtime : false
    }
    
    await mod.watch opt, defer(err, res); return on_end err if err
    {watcher} = res
    await setTimeout defer(), 500
    assert.strictEqual event_counter, 0
    
    watcher.close()
    
    on_end()
  
  it "with runtime", (on_end)->
    @timeout 10000
    event_counter = 0
    opt = {
      dir : "wasm_test/mod"
      on_recompile_done : ()->
        p "on_recompile_done EXT"
        event_counter++
    }
    
    await mod.watch opt, defer(err, res); return on_end err if err
    {watcher} = res
    await
      retry_cb ()->
        assert.strictEqual event_counter, 1
      , defer(err); return on_end err if err
    
    watcher.close()
    
    on_end()
  
  