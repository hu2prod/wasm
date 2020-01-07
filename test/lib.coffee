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
    do (seq)->
      it "compile test_wasm lib seq=#{seq}", (on_end)->
        execSync "rm test_wasm/lib/build/index.o 2>/dev/null ; echo -n ''"
        opt = {
          dir : "test_wasm/lib"
          seq
        }
        await mod.lib_compile opt, defer(err, res); return on_end err if err
        
        json_eq res, {
          obj_list : ["test_wasm/lib/build/index.o"]
        }
        
        assert fs.existsSync("test_wasm/lib/build/index.o"), "test_wasm/lib/build/index.o not exists"
        
        on_end()
        return
  
  for seq in [true, false]
    do (seq)->
      obj_list = ["test_wasm/lib/build/index.o"]
      # TODO seq/parallel
      it "compile test_wasm module seq=#{seq}", (on_end)->
        execSync "rm test_wasm/mod/index.wasm 2>/dev/null ; echo -n ''"
        execSync "rm test_wasm/mod/index.wat 2>/dev/null  ; echo -n ''"
        
        opt = {
          dir : "test_wasm/mod"
          obj_list
          seq
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
    buf = fs.readFileSync "test_wasm/mod/index.wasm"
    
    await WebAssembly.instantiate(buf, import_object).then(defer(instance))
    {
      export_me
    } = instance.instance.exports
    
    export_me()
    
    assert called, "logsi not called"
    
    on_end()