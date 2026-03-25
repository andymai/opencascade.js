// Patches all Embind-registered classes with [Symbol.dispose]() -> .delete()
// Injected via emcc --post-js during linking.
// Enables: using obj = new oc.gp_Pnt_3(0, 0, 0);
if (typeof Symbol !== 'undefined' && Symbol.dispose) {
  Module['onRuntimeInitialized'] = (function(origOnInit) {
    return function() {
      if (origOnInit) origOnInit.call(this);
      Object.keys(Module).forEach(function(key) {
        var obj = Module[key];
        if (obj && obj.prototype && typeof obj.prototype.delete === 'function'
            && !obj.prototype[Symbol.dispose]) {
          obj.prototype[Symbol.dispose] = obj.prototype.delete;
        }
      });
    };
  })(Module['onRuntimeInitialized']);
}
