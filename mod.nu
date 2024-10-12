# Open a toml file and error with a helpful message if it can't be parsed.
export def open-toml [path: path]: nothing -> record { ignore
    err-if (($path | path parse).extension != 'toml') {title: 'Not a TOML file' message: $"The file you are trying to open is not a TOML file: ($path | ft)"}
	try {
		open $path
	} catch {|err|
		$err
		| parse-error
		| update title "TOML parse error"
		| update message {|rec|
			$err.debug
			| parse -r '(?<hint>TOML parse error at line \d+, column \d+)'
			| get 0.hint
			| $in + $' in file ($path | ft file).'
		}
		| reject hint
		| error $in
	} 
}

# Run a closure on each row of the input list without disrupting the pipeline.
export def run-each [
	closure: closure   # A closure to run. Input: the repeat item (any). Parameters: the repeat item (any).
]: any -> any {
	let input = $in
	$input | each $closure
	$input
}

# Run a closure in parallel on each row of the input list without disrupting the pipeline.
export def run-par-each [
	closure: closure      # A closure to run. Input: the repeat item (any). Parameters: the repeat item (any).
	--threads (-t): int   # The number of threads to use. 
]: any -> any {
	let input = $in
	if $threads != null {
		$input | par-each --threads $threads $closure
	} else {
		$input | par-each $closure
	}
	$input
}

# Run a closure on the input without disrupting the pipeline.
export def run [
	closure: closure   # A closure to run. Input: the input (any). Parameters: the input (any).
]: any -> any {
	let input = $in
	$input | do $closure $input
	$input
}

# Run a closure on the input conditionally without disrupting the pipeline.
export def run-if [
	condition: bool    # A condition to check for.
	--not              # Negate the condition.
	closure: closure   # A closure to run. Input: the input (any). Parameters: the input (any).
]: any -> any {
	let input = $in
	if $condition xor $not { $input | do $closure $input }
	$input
}

# Convert the list into an English recounting.
export def recount [
	--and (-a)         # Delimit the last item with 'and' instead of 'or'.
	--no-quotes (-n)   # Don't put quotes around items.
]: list<string> -> string {
	do-if --not $no_quotes { each { $'"($in)"'} }
	| chunks ($in | length | [($in - 1), 1] | math max)
	| each { str join ', ' }
	| str join (
		if $and {' and '} else {' or '} 
	)
}

# Assigns default values to keys of a record or list of records.
export def defaults [defaults: record]: [list<record> -> list<record>, record -> record] {
    each {|it|
        $defaults
        | merge $it
    }
}

# Print a serialized value for debugging.
export def prt [
    value?: any   # The value to serialize. If no value is given, print the input instead.
    --json (-j)   # Serialize to json instead of nuon. You can also set $env.nuitron_prt_json environment variable for this.
]: any -> any {
	run {
		[$value, $in]
		| filter-one { first } 'prt: No value argument or input is provided.'
		| traverse {
			do-if (($in | describe) == closure) {'<Closure>'} 
		}
		| if ($json or $env.nuitron_prt_json? == true) {
			to json
		} else {
			to nuon	
		}
		| print $in
	}
}

# Say something to the user. 
# This command returns the input as-is.
export def say [
	...message: string   # The message to tell the user.
 	--ansi (-a): any     # (list<string> | string) Apply the given ANSI escape codes to the message
	--indent (-i): int   # Indent the meesage with spaces
	--output (-o)        # Output the constructed string instead of printing it
]: any -> any {

    # Prepend a green arrow character in front of the input.
    def arw [length: int]: nothing -> string { ignore
        1..($length - 1)
        | if $length > 1 { each { ' ' } }
        | str join ''
        | do-if ($length > 0) { $in + ('> ' | style green) }
    }

	let input = $in
	let indent = $indent | default 0
	$message
	| str join ''
	| do-if ($ansi != null) {|str|
		$ansi
		| do-if ($in | is-type 'string') { [$in] }
		| check-type --structured 'list<string>' -m {|value, value_type| $"say: The value given to flag --ansi (-a) has a type of ($value_type): \n$value \n\n The type of the value must be either string or list<string>."}
		| reduce {|it, acc| $acc | style $it } -f $str
	}
	| $"(arw $indent)($in)"
	| do-if --not $output {
		print $in
		$input
	}
}

# Print an error with the given message.
# If the $env.nuitron_exit_on_error environment variable is set to true, exit the shell after printing the error.
export def error [
	message: any            # (string | record) An error message string or a record with fields <message: string, title?: string, hint?: string, source?: string> to display.
	--hint (-h): string     # (optional) Display a hint
	--title (-t): string    # (optional) Display a title
	--source (-s): string   # (optional) Display a source for the error
]: nothing -> nothing { ignore
	let record = do-if ($message | is-type record) {$message}
	if $record != null and (
		($record.message? | is-type --not string) or
		($record.hint? | is-type --not string nothing) or
		($record.title? | is-type --not string nothing) or
		($record.source? | is-type --not string nothing) or
		not ($record | columns | all-in [message hint title source])
	) {
		(_error $"The given error message doesn't match type ('record<message: string, hint?: string, title?: string, source?: string>' | ft type): \n\n($record)" 
			$"Run ('error --help' | ft cmd) for more information."
			$"Type mismatch" 
			'error')
	}
	
	let message = if $record != null { $record.message } else { $message }
	let hint = if $record != null { $record.hint? } else { $hint }
	let title = if $record != null { $record.title? } else { $title }
	let source = if $record != null { $record.source? } else { $source }

	def _error [message, hint?, title?, source?] {
		let no_title = $title == null
		let title = if $no_title { $message } else { $title }
		let message = if $no_title {} else { $message }
		if ($title | str contains "\n") {
			(_error $"The text of the provided error contains newlines: \n($title | to nuon)" 
				$"Remove newlines from the (if $no_title {"message"} else {"title"})." 
				$"Newlines in provided error text" 
				'error')
		}
		if $source != null and ($source | parse -r '\s' | is-not-empty) {
			(_error $"The source of the provided error contains whitespace: \n($source)" 
				"Remove whitespace from the source."
				$"Whitespace in provided error source" 
				'error')
		}
		$"(('Error' | style red) + ':' | style attr_bold)   ('×' | style red) (if $source != null {$source | style navy attr_bold | $in + ': '} else {''} )($title | do-if --not $no_title {style attr_bold })"
		| do-if ($message != null) { 
			$in + "\n ├\n" + (($message | str trim) + (if $hint != null {"\n"} else {''}) | str replace --all -m '^(.*)$' $" │ $1")
			| if ($hint == null) { 
				$in + "\n └" 
			} else {
				$in + "\n ╰── "
			}
		}
		| do-if ($hint != null) { $in + ($'hint: ($hint)' | style blueviolet attr_bold) }
		| print $in
		if ($env.nuitron_exit_on_error? == true) {
			exit ($env.nuitron_error_exit_code? | default 1)
		}
	}
	
	_error $message $hint $title $source
}

# Get the base type of a value provided either as an argument or from the input. 
# Base types comprise 'list', 'record', and all basic types. Tables are recognized as lists.
export def type-of [value: any]: nothing -> string { ignore
	$value
	| describe --detailed
	| get type
}

# Run a closure on every basic value contained in structured values.
export def traverse [
	closure?: closure            # If given, run this closure on every basic value. Parameters: the input value (any). Input: the basic value (any).
	--structured (-s): closure   # If given, run this closure on structured values themselves and use the output for further traversal. Parameters: the input value (any). Input: the structured value (any). 
	--keep-input (-k)    	     # Output the input unchanged.
]: any -> any {
	let input = $in | collect
	def _traverse [closure: closure, structured: closure]: any -> any {
		match (type-of $in) {
			'list' => {
				do $structured $input
				| each {|it|
					$it | _traverse $closure $structured
				}
			}
			'record' => {
				do $structured $input
				| items {|key, value|
					$value
					| _traverse $closure $structured
					| {$key: $in}
				}
				| reduce -f {} {|it, acc| $acc | merge $it}
			}
			_ => {
				do-if ($closure != null) {
					do $closure $input
				}
			}
		}
	}
	$input
	| _traverse ($closure | default {||}) ($structured | default {||})	
	| do-if $keep_input { $input }
}


# Check that the input list has only one non-nothing item. If so, return it. Otherwise error with given message.
export def filter-one [
	multiple: any               # (string | closure) If multiple items match, error with the given message string or execute the given closure on matching items and return the result. Input: matching items (list<any>). Parameters: input list (list<any>). Output: string.
	none_err?: any              # (string | record) If given, error with the given string or description if no items match. Error description syntax is the same as 'error' command.
	--allow-none (-n)           # If given, don't error if no items match.
	--predicate (-p): closure   # If given, test whether elements in the input list fullfill this predicate instead. Input: input list (list<any>). Parameters: repeat item (any). Output: bool.
]: list<any> -> any {
	let input = $in | collect
	if $allow_none == false and $none_err == null {
		error "filter-one: You left the second argument \"none_err\" empty but you didn't specify the \"--allow-none (-n)\" flag."
	}
	let multiple_type = $multiple | describe
	if not ($multiple | is-type 'string' 'closure') {
		error $'filter-one: Received a value with a type of "($multiple_type)" for "multiple" argument. The value must have a type of either string or closure.'
	}	
	$input
	| filter ($predicate | default {|it| $it != null})
	| match ($in | length) {
		0 => { do-if ($none_err != null) { error $none_err } },
		1 => { $in | first },
		_ => {
			if $multiple_type == closure {
				do $multiple $input
			} else if $multiple_type == string {
				error $multiple
			}
		}
	}
}

# Check type of input, and throw an error if it doesn't match.
export def check-type [
	...types: string          # Type descriptions to check for. Syntax is the same as 'describe' command output.
	--source (-s): string     # Source of the value. If given, create an error message with the source.
	--err-msg (-m): closure   # A closure to generate a customized error message with. Parameters: input value (any), input value type (string), an English recounting of accepted types (string). Expected output: {message: string, hint: hint}.
	--loc-str (-l): string    # A string describing where the value came from. If given, generate an error message with this string.
	--structured (-e)         # Match nested/structured data types, instead of just the base type.
	]: any -> any {
	let input = $in

	let error = (
		[
			[name       value       flag             ];
			[source     $source     '--source (-s)']
			[err-msg    $err_msg    '--err-msg (-m)' ]
			[loc-str    $loc_str    '--loc-str (-l)' ]
		] 
		| filter-one --predicate {|row| $row.value != null}
			{error -s 'check-type' --title "Multiple flags provided" $"You provided ($in | columns | recount --and) flags. Please provide only one." }
			{source: 'check-type', title: 'Necessary flags are not provided', message: $'You must provide at least one of the flags ($in | columns | recount).' }
	)
	$types | _check-type {types: ['list<string>'], source: 'check-types', structured: true}
	$input | _check-type {types: $types, source: $source, structured: $structured}
	
	def _check-type [args: record<types: list<string>, source: any, structured: bool>]: any -> nothing {
		let value = $in
		let types = $args.types
		let source = $args.source
		let structured = $args.structured

		if $structured {
			$value | is-type --structured ...$types
		} else {
			$value | is-type ...$types
		}
		| if not $in {
			let types_str: string = $types	| each {ft type} | recount --no-quotes
			let value_type: string = $value | describe
			match $error.name {
				source => { source: $error.value, message: $"The given value has a type of ($value_type | ft type): \n($value)", hint: $"Accepted types are ($types_str)." }
				loc-str => { message: $"The specified value ($error.value) has a type of ($value_type | ft type): \n($value)", hint: $"Accepted types are ($types_str)." }
				err-msg => { 
					do $error.value $value $value_type $types_str 
					| err-if ((not ($in | is-type 'record')) or ($in.message? == null or $in.hint? == null)) $"check-type: Output of the closure passed in with --err-msg \(-m\) flag doesn't match the type ('record<message: string, hint: string, title?: string>' | ft type)."
				}
			}
			| {title: "Type mismatch", ...$in}
			| error $in
		}
	}

	$input
}

# Check whether the input matches a given list of types.
export def is-type [
	...types: string    # Type descriptions to check for. Syntax is the same as 'describe' command output.
	--structured (-e)   # Match nested/structured data types, instead of just the base type.
	--not               # Negate the result.
	]: any -> any {
	let value = $in
	let value_type: string = do {
		$value 
		| describe
		| do-if (not $structured) { get-basic-type }
	}
	$types
	| err-if-any {|type|
		let is_structured_type = ($type | get-basic-type) != $type
		$structured != $is_structured_type
	} {|type|
		if $structured {
			$"is-type: You specified the --structured \(-s\) flag but provided a basic data type to check against: \"($type)\". \nPlease provide a structured type instead, like \"list<string>\"."
		} else {
			let simple_type: string = $type | get-basic-type
			$"is-type: You didn't specify the --structured \(-s\) flag but provided a structured data type to check against: \"($type)\". \nPlease provide a simple type instead, like \"($simple_type)\"."
		}
	}

	($value_type in $types) or (	
		# An empty list should match a list containing any type.
		# TODO: The current method can't work on lists nested inside other data types. For this to work, we need to match the output of describe --detailed. It contains information about whether the list is empty too.
		$value_type == 'list<any>' and
		($value | is-empty ) and
		($types | any {($in | get-basic-type) == 'list'})
	)
	| $in xor $not
}

# Get the basic type from a type description. 
# This differs from the nuitron type-of function in that it recognizes table as a type.
export def get-basic-type []: string -> string {
	str replace --regex '<.*' ''
}

# Check values in a pipeline against a condition and error if check fails.
# The difference with each { err-if } is err-if-any will only accept list input.
export def err-if-any [
	condition: closure   # A condition to check with every item. Input: repeat item (any). Parameters: repeat item (any). Output: bool.
	error_msg: closure   # A closure to generate an error message with. Input: failed item (any). Parameters: failed item (any), input list (list<any>). Output: (string | record).
	--not                # Negate the condition.
]: [list<any> -> list<any>] {
	let list = $in
	$list
	| each {|it|
		err-if ($not xor ($it | do $condition $it)) ($it | do $error_msg $it $list)
	}
}

# Check the input against a condition and error if check passes.
export def err-if [
	condition: bool   # A condition to check for.
	message: any      # (string | record) An error message string or a record with fields <message: string, title?: string, hint?: string> to display.
	--not             # Negate the condition.
]: any -> any {
	do-if ($condition xor $not) {
		error $message
	}
}

# Conditionally run a closure on the input.
export def do-if [
	condition: bool   # A condition to check for.
	--not             # Negate the condition.
	then: closure     # A closure to run on input if the condition is true. Input: input (any). Parameters: input (any).
]: any -> any {
	if $condition xor $not {
		$in | do $then $in
	} else { $in }
}

# Run a block with the input passed as the first parameter.
export def with [
	closure: closure   # The closure to run.
]: any -> any {
	do $closure $in
}

# Test if every element in the input is an item in a list, is part of a string, or is a key in a record.
export def all-in [
	operand: any            # A string, list, or record to check inclusion in.
	--error (-e): closure   # If given, create an error if any given item is not in the input, with an error message created with the given closure. Input: nonexistent item (any). Parameters: nonexistent item (any), the operand (any). Output: string.
]: list<any> -> bool {
	if $error != null {
		err-if-any {|it| $it not-in $operand} {|it| $it | do $error $it $operand}
	} else {
		all {|it| $it in $operand }
	}
}

# Construct a file name from a URL.
export def 'url to-filename' []: string -> string {
	def get_last_component []: string -> string { parse -r '^.*?([/\\](?<it>[^/\\]{3,255})[^/\\]*)?$' | get it.0 }
	$in
	| url parse
	| with {|it|
		$in.path
		| url decode
		| get_last_component
		| path sanitize
		| do-if (($in | str length) < 3) {
			$it.host + ($it.path | url decode)
			| path sanitize
		}
	}
}

# Sanitize a string to use as a file name.
export def 'path sanitize' []: string -> string {
	str replace -ra '[\/\?<>\\:\*\|"]'  ''                                  # Windows illegal filename characters
	| str replace -ra '~' ''                                                # Unix home character
	| str replace -ra '[\x00-\x1f\x80-\x9f]' ''                             # Control characters
	| str replace -ra '(?i)^(con|prn|aux|nul|com[0-9]|lpt[0-9])(\..*)?$' '' # Windows reserved names
	| str replace -r '[. ]+$' ''                                            # Windows illegal trailing dot and whitespace
	| str substring ..255                                                   # Windows filename max length
	| str replace -r '^\.+$' ''                                             # Reserved for navigation
}

# Find a directory with the given name in parent directories. If not found, returns nothing.
export def find-dir [ 
	dir_name: string   # Name of the directory to find.
]: nothing -> any { ignore
	if ($env.PWD | path parse | get parent | is-empty) {
		return null
	}
	ls
	| where name == $dir_name
	| if ($in | is-empty) or ($in.0.type != dir) {
		cd ..
		find-dir $dir_name
	} else {
		return ($in.name.0 | path expand )
	}
}

# Apply ansi escape codes to the start of the piped text and reset text styling at the end.
export def style [
    ...code: string   # The ansi escape codes to apply.
]: string -> string {
	with {|str|
		$code
		| reduce -f $str {|it, acc|
			$"(ansi $it)($acc)"
		}
		| $"($in)(ansi reset)"
	}
}

# Ensure a directory exists at a certain path.
export def ensure-dir [
	dir_path: path   # The path to directory.
	--empty          # Error if directory already exists AND is not empty.
] {
	let path: path = $dir_path | path split | path join
	if not ($path | path exists) {
		mkdir $path
	}
	let type: string = (ls -D $path).type.0
	if $type != dir {
		error $"Can't create the directory ($path). There is already an item named ($path | path basename | ft $type) in ($path | path dirname | ft dir)."
	}
	if $empty and (ls $path | is-not-empty) {
		error $"Can't create the directory ($path | ft dir). There is already a non-empty directory at ($path | ft dir)\"."
	}
}

# Format the input for display with a predefined style.
# If no style is given and the item is a file, directory or a symlink the corresponding style is used instead. If no style can be determined, the input will be returned unchanged.
# Check out the source code for styles and their names.
export def ft [type?: string]: string -> string {
	let path = $in
	let type = (
		$type | default (
			do-if ($path | path exists) {
				ls -D $path
				| get 0.type
			}
		)
	)
	match $type {
		'path'    => [ xyellow ]                     # Path to unknown item.
		'file'    => [ olive ]                       # File path.
		'dir'     => [ light_cyan ]                  # Directory path.
		'symlink' => [ xpurplea ]                    # Symlink path.
		'cmd'     => [ light_purple_bold ]           # Shell command.
		'key'     => [ mediumturquoise attr_bold]    # A key in user input (e.g in a TOML, JSON, YAML etc. file.)
		'type'    => [ cyan ]                        # A type description.
		'input'   => [ grey62 ]                      # Unknown, invalid or unrecognized user input.
		'depset'  => [ light_blue_bold ]             # This is for use in Depman. TODO: Separate this into Depman repo.
		'dep'     => [ yellow_bold ]                 # Same as above. 
	}
	| with {|code|
		$path
		| do-if ($type == dir) { path split | path join | $in + (char path_sep) }
		| do-if ($type == input) { $'"($in)"'}
		| do-if ($code != null) { style ...$code }
	}
}

# Parse an error returned in a catch statement into a standardized format.
# You can use the returned value directly with nuitron error command.
export def parse-error []: record<msg: string, debug: string, raw: error> -> record<title: string, message: string, hint: string> {
	let $err = $in | check-type --structured 'record<msg: string, debug: string, raw: error>' --source 'parse-error' # todo check actually matters
	let type = $err.debug | parse -r '^(?<type>\w+)' | get 0.type
	$err.debug
	| str replace -r $'^($type) ' ''
	| str replace --all -r 'Some\((.*?)\)' '$1'
	| str replace --all -r ', \w+: Span {.+?}' ''
	| from nuon
	| with {|struct|
		let message = (
			match $type {
				UnsupportedInput => {
					$struct.input | parse "value: '\"{value}\"'"
					| $"($struct.msg)\nThe received input: ($in)"
				}
				DirectoryNotFound => { $"Can't find the directory at path ($struct.dir | ft dir)" }
				_ => { $struct.msg }
			}
		)
		{
			title: $err.msg,
			message: $message,
			hint: $struct.help?
		}
	}
}