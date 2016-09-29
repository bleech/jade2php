<?php

error_reporting(E_ALL & ~E_NOTICE);

function attr($name, $value = true, $escaped = true) {
	if (!empty($value)) {
		echo " $name=\"$value\"";
	}
}

function pug_attr($key, $val, $escaped, $terse) {
	if ($val === false || $val == null || !isset($val) && ($key === 'class' || $key === 'style')) {
    echo '';
		return;
  }
  if ($val === true) {
    echo ' ' . (isset($terse) ? $key : $key . '="' . $key . '"');
		return;
  }

  if ($escaped) $val = pug_escape($val);
  echo ' ' . $key . '="' . $val . '"';
};


function pug_attrs($obj, $terse){
	$attrs = [];

	if(isset($obj['class'])) {
		$key = 'class';
		$val = $obj['class'];
		$val = pug_classes($val);
		$attrs[] = pug_attr($key, $val, false, $terse);
	}

  foreach($obj as $key => $val) {
    if ('class' === $key) {
      continue;
    }
    $attrs[] = pug_attr($key, $val, false, $terse);
  }
  return $attrs;
};

function pug_classes_array($values, $escaping) {
  $classString = '';
	$className = null;
	$padding = '';
	$escapeEnabled = is_array($escaping);
  foreach ($values as $i => $val) {
    $className = pug_classes($val);
    if (!$className) continue;
    $escapeEnabled && $escaping[$i] && ($className = pug_escape($className));
    $classString = $classString . $padding . $className;
    $padding = ' ';
  }
  return $classString;
}
function pug_classes_object($classes) {
  $classString = '';
	$padding = '';
  foreach ($classes as $key => $val) {
    if ($key && $val) {
      $classString = $classString . $padding . $key;
      $padding = ' ';
    }
  }
  return $classString;
}
function pug_classes($val, $escaping) {
  if (is_array($val)) {
    return pug_classes_array($val, $escaping);
  } else {
    return isset($val) ? $val : '';
  }
}

function pug_escape($html){
  return htmlspecialchars($html);
};

function attrs() {
	$args = func_get_args();
	$attrs = array();
	foreach ($args as $arg) {
		foreach ($arg as $key => $value) {
			if ($key == 'class') {
				if (!isset($attrs[$key])) $attrs[$key] = array();
				$attrs[$key] = array_merge($attrs[$key], is_array($value) ? $value : explode(' ', $value));
			} else {
				$attrs[$key] = $value;
			}
		}
	}
	foreach ($attrs as $key => $value) {
		if ($key == 'class') {
			attr_class($value);
		} else {
			attr($key, $value);
		}
	}
}

function attr_class() {
	$classes = array();
	$args = func_get_args();
	foreach ($args as $arg) {
		if (empty($arg) || is_array($arg) && count($arg) == 0) continue;
		$classes = array_merge($classes, is_array($arg) ? $arg : array($arg));
	}
	$classes = array_filter($classes);
	if (count($classes) > 0) attr('class', join(' ', $classes));
}

function add() {
	$result = '';
	$args = func_get_args();
	$concat = false;
	foreach ($args as $arg) {
		if ($concat || is_string($arg)) {
			$concat = true;
			$result .= $arg;
		} elseif (is_numeric($arg)) {
			if ($result === '') $result = 0;
			$result += $arg;
		}
	}
	return $result;
}
?>
