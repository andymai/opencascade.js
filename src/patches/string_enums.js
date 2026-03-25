// Adds string representation to all Embind enum members.
// Injected via emcc --post-js during linking.
//
// After this patch, enum members have:
// - .toString() returning the member name (e.g., 'TopAbs_SOLID')
// - .valueOf() returning the member name as a string
// - JSON.stringify() producing the member name
//
// The numeric .value property is preserved for Embind C++ marshalling.
if (!Module['postRun']) Module['postRun'] = [];
Module['postRun'].push(function() {
  Object.keys(Module).forEach(function(key) {
    var obj = Module[key];
    // Embind enums have a 'values' object whose members each have a numeric .value
    if (obj && typeof obj === 'object' && obj.values && typeof obj.values === 'object') {
      var names = Object.keys(obj.values);
      // Verify this is actually an enum (first member has numeric .value)
      var first = obj.values[names[0]];
      if (!first || typeof first.value !== 'number') return;
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
});
