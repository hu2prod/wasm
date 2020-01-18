assert = require "assert"
fs = require "fs"
# mod = require "../src/lib"
mod = require "../src/index"
# but test only lib part

{execSync} = require "child_process"
json_eq = (a, b)->
  assert.strictEqual JSON.stringify(a, null, 2), JSON.stringify(b, null, 2)

# 2>/dev/null suppresses stderr
#  ; echo -n '' suppresses error code 1

describe "lib section", ()->
  # TODO seq/parallel
  for seq in [true, false]
    for drop_clang_warning in [true, false]
      do (seq, drop_clang_warning)->
        it "compile wasm_test lib seq=#{seq}", (on_end)->
          execSync "rm wasm_test/lib/build/index.o 2>/dev/null ; echo -n ''"
          opt = {
            dir : "wasm_test/lib"
            seq
            drop_clang_warning
          }
          await mod.lib_compile opt, defer(err, res); return on_end err if err
          
          json_eq res, {
            obj_list : ["wasm_test/lib/build/index.o"]
          }
          
          assert fs.existsSync("wasm_test/lib/build/index.o"), "wasm_test/lib/build/index.o not exists"
          
          on_end()
          return
    
  for seq in [true, false]
    for drop_clang_warning in [true, false]
      do (seq, drop_clang_warning)->
        obj_list = ["wasm_test/lib/build/index.o"]
        # TODO seq/parallel
        it "compile wasm_test module seq=#{seq}", (on_end)->
          execSync "rm wasm_test/mod/index.wasm 2>/dev/null ; echo -n ''"
          execSync "rm wasm_test/mod/index.wat  2>/dev/null ; echo -n ''"
          
          opt = {
            dir : "wasm_test/mod"
            obj_list
            seq
            drop_clang_warning
            use_wasm_runtime : false
          }
          await mod.mod_compile opt, defer(err); return on_end err if err
          
          on_end()
          return
  
  it "run compiled wasm", (on_end)->
    memory = null
    called = false
    import_object = {
      env :
        logsi : (s, i)->
          # TBD get string
          assert.strictEqual i, 0, "i != 0"
          called = true
    }
    buf = fs.readFileSync "wasm_test/mod/index.wasm"
    
    await WebAssembly.instantiate(buf, import_object).then(defer(instance))
    {
      export_me
    } = instance.instance.exports
    
    export_me()
    
    assert called, "logsi not called"
    
    on_end()
  
  