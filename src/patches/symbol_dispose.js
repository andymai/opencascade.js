// Patches all Embind-registered classes with [Symbol.dispose]() -> .delete()
// Injected via emcc --post-js during linking.
// Enables: using obj = new oc.gp_Pnt_3(0, 0, 0);
if (typeof Symbol !== 'undefined' && Symbol.dispose) {
  if (!Module['postRun']) Module['postRun'] = [];
  Module['postRun'].push(function() {
    Object.keys(Module).forEach(function(key) {
      var obj = Module[key];
      if (obj && obj.prototype && typeof obj.prototype.delete === 'function'
          && !obj.prototype[Symbol.dispose]) {
        obj.prototype[Symbol.dispose] = obj.prototype.delete;
      }
    });
  });
}
