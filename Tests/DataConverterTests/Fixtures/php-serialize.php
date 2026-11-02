<?php
// Writes php-serialize.json: values serialized by PHP itself, each with the tree PHPSerialized must
// read from it, computed here from PHP's OWN unserialize() (an independent parser). The tree rules:
// a list array (keys 0..n-1 in order) is a sequence, any other array a mapping with its keys as
// strings; an object is a mapping whose first key is "__class", a protected property named
// "name:protected" and a private one "name:Class:private" (print_r's words); an enum case is the
// string "Enum::Case"; INF, -INF and NAN are those strings; a string's bytes are read as UTF-8, a
// bad sequence as U+FFFD. Nested serialized values are left as strings here (no expansion).
// Run: php php-serialize.php out.json
mt_srand(20261102);
mb_substitute_character(0xFFFD);

class Point { public $x = 1; protected $y = 2; private $z = 3; public function __construct($x = 1, $y = 2, $z = 3) { $this->x = $x; $this->y = $y; $this->z = $z; } }
class Child extends Point { private $z = 'child'; public $tags = []; }
class Account { public function __construct(public string $id = '', public ?Account $parent = null) {} }
class Money { public function __construct(private int $cents = 0, private string $currency = 'GBP') {}
    public function __serialize(): array { return ['c' => $this->cents, 'cur' => $this->currency]; }
    public function __unserialize(array $d): void { $this->cents = $d['c']; $this->currency = $d['cur']; } }
enum Suit { case Hearts; case Spades; }
enum Status: string { case Active = 'active'; case Banned = 'banned'; }

function tree($v, array &$seen = []) {
    if ($v === null || is_bool($v) || is_int($v)) return $v;
    if (is_float($v)) {
        if (is_nan($v)) return 'NAN';
        if (is_infinite($v)) return $v > 0 ? 'INF' : '-INF';
        return $v;
    }
    if (is_string($v)) return mb_convert_encoding($v, 'UTF-8', 'UTF-8') === $v ? $v : utf8($v);
    if ($v instanceof UnitEnum) return get_class($v) . '::' . $v->name;
    if (is_object($v)) {
        $id = spl_object_id($v);
        if (in_array($id, $seen, true)) return '*RECURSION*';
        $seen[] = $id;
        $class = get_class($v);
        $props = (array) $v;
        if ($v instanceof __PHP_Incomplete_Class) { $class = $props['__PHP_Incomplete_Class_Name']; unset($props['__PHP_Incomplete_Class_Name']); }
        if ($v instanceof Money) { $props = $v->__serialize(); }
        $out = ['__class' => $class];
        foreach ($props as $k => $p) {
            $k = (string) $k;
            if (str_starts_with($k, "\0*\0")) $k = substr($k, 3) . ':protected';
            elseif (str_starts_with($k, "\0")) { [, $owner, $name] = explode("\0", $k, 3); $k = "$name:$owner:private"; }
            $out[$k] = tree($p, $seen);
        }
        array_pop($seen);
        return (object) $out;
    }
    if (is_array($v)) {
        if (array_is_list($v)) return array_map(fn($x) => tree($x, $seen), $v);
        $out = [];
        foreach ($v as $k => $x) $out[(string) $k] = tree($x, $seen);
        return (object) $out;
    }
    throw new Exception('unexpected ' . gettype($v));
}
// A string with bad UTF-8: each maximal bad subsequence becomes one U+FFFD, the Unicode practice
// that Swift's String(decoding:as:) follows; mb_scrub follows it too.
function utf8(string $s): string { return mb_scrub($s, 'UTF-8'); }

function randomString(): string {
    $pool = ['', 'a', 'Sample array', 'quote " inside', 'semi;colon', 'brace } and {', '";', 's:3:"abc";', "line\nbreak", "tab\there",
        'Kraków', 'Москва', '東京', 'emoji 🎉 here', "nul\0byte", 'back\\slash', '0', '08', '-1', '1.5', 'true', 'N;', 'a:0:{}'];
    return $pool[mt_rand(0, count($pool) - 1)];
}
function randomScalar() {
    switch (mt_rand(0, 9)) {
        case 0: return null;
        case 1: return (bool) mt_rand(0, 1);
        case 2: return mt_rand(-1000, 1000);
        case 3: return [PHP_INT_MAX, PHP_INT_MIN, 0, -1][mt_rand(0, 3)];
        case 4: return [0.1, -0.0, 1.5e-7, 1e100, 3.141592653589793, -2.5, 1.0][mt_rand(0, 6)];
        default: return randomString();
    }
}
function randomValue(int $depth) {
    if ($depth <= 0 || mt_rand(0, 3) === 0) return randomScalar();
    $n = mt_rand(0, 4);
    switch (mt_rand(0, 3)) {
        case 0: $a = []; for ($i = 0; $i < $n; $i++) $a[] = randomValue($depth - 1); return $a;
        case 1: $a = []; for ($i = 0; $i < $n; $i++) {
                    $k = mt_rand(0, 2) === 0 ? mt_rand(-5, 50) : randomString();
                    $a[$k] = randomValue($depth - 1);
                } return $a;
        case 2: $o = new stdClass; for ($i = 0; $i < $n; $i++) { $o->{'p' . $i} = randomValue($depth - 1); } return $o;
        default: return new Point(randomValue($depth - 1), randomValue($depth - 1), randomValue($depth - 1));
    }
}

$cases = [];
function add(string $name, $value) {
    global $cases;
    $s = serialize($value);
    $cases[] = ['name' => $name, 'serialized' => base64_encode($s), 'tree' => tree(unserialize($s))];
}
// The README example, and every kind once.
add('sample array', ['Sample array', ['Apple', 'Orange']]);
add('null', null); add('true', true); add('false', false);
add('int max', PHP_INT_MAX); add('int min', PHP_INT_MIN);
add('floats', [0.1, -0.0, 1.5e-7, 1e100, 1.0, 2.5e-308]);
add('inf and nan', [INF, -INF, NAN]);
add('multibyte', ['Kraków', 'Москва', '東京', '🎉', "a\"b;c}d"]);
add('bad utf-8', ["ok \xff\xfe bytes", "\xc3", "trail \xe2\x82"]);
add('empty', ['', [], new stdClass]);
add('sparse and negative keys', [3 => 'a', -1 => 'b', 0 => 'c']);
add('numeric string keys', ['08' => 'stays a string key', '8' => 'becomes int 8', '1.5' => 'string']);
add('list after unset', (function () { $a = ['a', 'b', 'c']; unset($a[1]); return $a; })());
add('object visibility', new Point(10, 20, 30));
add('inherited private', new Child());
add('typed and nested object', new Account('child', new Account('root')));
add('__serialize', new Money(1999, 'EUR'));
add('enums', [Suit::Hearts, Status::Banned, 'k' => Suit::Spades]);
add('recursion', (function () { $o = new stdClass; $o->self = $o; $o->name = 'loop'; return $o; })());
add('shared object', (function () { $p = new Point; return [$p, $p]; })());
add('numbering after a handle', (function () { $p = new Point(1, 1, 1); $q = new Point(2, 2, 2); return [$p, $p, $q, $q, 'x' => [&$q->x]]; })());
add('reference', (function () { $a = ['x' => 1]; $a['y'] = &$a['x']; return $a; })());
add('wordpress option', ['widget_text' => [2 => ['title' => 'About', 'text' => '<p>Hello "world"</p>', 'filter' => true], '_multiwidget' => 1]]);
add('double serialized', serialize(['inner' => 'value']));
add('json inside', ['payload' => json_encode(['id' => 7, 'tags' => ['a', 'b']])]);
add('incomplete class', unserialize('O:12:"MissingClass":2:{s:3:"one";i:1;s:6:"' . "\0*\0" . 'two";i:2;}'));
add('deep', array_reduce(range(1, 40), fn($acc, $i) => ['level' => $i, 'next' => $acc], 'bottom'));
for ($i = 0; $i < 300; $i++) add("random $i", randomValue(4));

$json = json_encode($cases, JSON_PRESERVE_ZERO_FRACTION | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT | JSON_THROW_ON_ERROR);
file_put_contents($argv[1], $json . "\n");
echo count($cases) . " cases\n";
