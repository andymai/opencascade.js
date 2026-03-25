// Adds string representation to all Embind enum members.
// Injected via emcc --post-js during linking.
//
// After this patch, enum members have:
// - .toString() returning the member name (e.g., 'TopAbs_SOLID')
// - .valueOf() returning the member name as a string
// - JSON.stringify() producing the member name
//
// The numeric .value property is preserved for Embind C++ marshalling.
Module['onRuntimeInitialized'] = (function(origOnInit) {
  return function() {
    if (origOnInit) origOnInit.call(this);
    Object.keys(Module).forEach(function(key) {
      var obj = Module[key];
      if (obj && typeof obj === 'object' && obj.values && typeof obj.values === 'object') {
        var names = Object.keys(obj.values);
        for (var i = 0; i < names.length; i++) {
          var name = names[i];
          var member = obj[name];
          if (member && typeof member === 'object') {
            member.toString = (function(n) { return function() { return n; }; })(name);
            member.valueOf = member.toString;
            member.toJSON = member.toString;
          }
        }
      }
    });
  };
})(Module['onRuntimeInitialized']);
