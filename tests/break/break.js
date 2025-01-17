function foo(b) {
    var x = b ? null: false;
    var z;
    while(b) {
        if (x == null) { z = ""; break; }
        var y:number = x; // error: boolean !~> number
    }
    var w:number = z; // 2 errors: ?string !~> number
}

function bar(b) {
    var x = b ? null: false;
    if (x == null) return;
    switch ("") {
    case 0:
        var y:number = x; // error: boolean !~> number
        x = "";
    case 1:
        var z:number = x; // 2 errors: (boolean | string) !~> number
        break;
    case 2:
    }
    var w:number = x; // 2 errors: (boolean | string) !~> number
}

function bar2(b) {
    var x = b ? null: false;
    if (x == null) return;
    switch ("") {
    case 0: {
      let y:number = x; // error: boolean !~> number
      x = "";
    }
    case 1: {
      let z:number = x; // 2 errors: (boolean | string) !~> number
      break;
    }
    case 2:
    }
    var w:number = x; // 2 errors: (boolean | string) !~> number
}

function qux(b) {
    var z: number | string = 0;
    while(b) {
        var y:number = z;
        if (b) { z = ""; continue; } // error: string !~> number
        z = 0;
    }
    var w:number = z; // error: string !~> number
}

// same basic test as foo(), but with const. probes the
// logic that still uses havoc to do env resets.
function test_const() {
  let st: string = 'abc';

  for (let i = 1; i < 100; i++) {
    const fooRes: ?string = "HEY";
    if (!fooRes) {
      break;
    }

    st = fooRes; // no error
  }

  return st;
}
