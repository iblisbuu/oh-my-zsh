#compdef ark

__ark_bash_source() {
	alias shopt=':'
	alias _expand=_bash_expand
	alias _complete=_bash_comp
	emulate -L sh
	setopt kshglob noshglob braceexpand
	source "$@"
}
__ark_type() {
	# -t is not supported by zsh
	if [ "$1" == "-t" ]; then
		shift
		# fake Bash 4 to disable "complete -o nospace". Instead
		# "compopt +-o nospace" is used in the code to toggle trailing
		# spaces. We don't support that, but leave trailing spaces on
		# all the time
		if [ "$1" = "__ark_compopt" ]; then
			echo builtin
			return 0
		fi
	fi
	type "$@"
}
__ark_compgen() {
	local completions w
	completions=( $(compgen "$@") ) || return $?
	# filter by given word as prefix
	while [[ "$1" = -* && "$1" != -- ]]; do
		shift
		shift
	done
	if [[ "$1" == -- ]]; then
		shift
	fi
	for w in "${completions[@]}"; do
		if [[ "${w}" = "$1"* ]]; then
			echo "${w}"
		fi
	done
}
__ark_compopt() {
	true # don't do anything. Not supported by bashcompinit in zsh
}
__ark_ltrim_colon_completions()
{
	if [[ "$1" == *:* && "$COMP_WORDBREAKS" == *:* ]]; then
		# Remove colon-word prefix from COMPREPLY items
		local colon_word=${1%${1##*:}}
		local i=${#COMPREPLY[*]}
		while [[ $((--i)) -ge 0 ]]; do
			COMPREPLY[$i]=${COMPREPLY[$i]#"$colon_word"}
		done
	fi
}
__ark_get_comp_words_by_ref() {
	cur="${COMP_WORDS[COMP_CWORD]}"
	prev="${COMP_WORDS[${COMP_CWORD}-1]}"
	words=("${COMP_WORDS[@]}")
	cword=("${COMP_CWORD[@]}")
}
__ark_filedir() {
	local RET OLD_IFS w qw
	__ark_debug "_filedir $@ cur=$cur"
	if [[ "$1" = \~* ]]; then
		# somehow does not work. Maybe, zsh does not call this at all
		eval echo "$1"
		return 0
	fi
	OLD_IFS="$IFS"
	IFS=$'\n'
	if [ "$1" = "-d" ]; then
		shift
		RET=( $(compgen -d) )
	else
		RET=( $(compgen -f) )
	fi
	IFS="$OLD_IFS"
	IFS="," __ark_debug "RET=${RET[@]} len=${#RET[@]}"
	for w in ${RET[@]}; do
		if [[ ! "${w}" = "${cur}"* ]]; then
			continue
		fi
		if eval "[[ \"\${w}\" = *.$1 || -d \"\${w}\" ]]"; then
			qw="$(__ark_quote "${w}")"
			if [ -d "${w}" ]; then
				COMPREPLY+=("${qw}/")
			else
				COMPREPLY+=("${qw}")
			fi
		fi
	done
}
__ark_quote() {
    if [[ $1 == \'* || $1 == \"* ]]; then
        # Leave out first character
        printf %q "${1:1}"
    else
    	printf %q "$1"
    fi
}
autoload -U +X bashcompinit && bashcompinit
# use word boundary patterns for BSD or GNU sed
LWORD='[[:<:]]'
RWORD='[[:>:]]'
if sed --help 2>&1 | grep -q GNU; then
	LWORD='\<'
	RWORD='\>'
fi
__ark_convert_bash_to_zsh() {
	sed \
	-e 's/declare -F/whence -w/' \
	-e 's/_get_comp_words_by_ref "\$@"/_get_comp_words_by_ref "\$*"/' \
	-e 's/local \([a-zA-Z0-9_]*\)=/local \1; \1=/' \
	-e 's/flags+=("\(--.*\)=")/flags+=("\1"); two_word_flags+=("\1")/' \
	-e 's/must_have_one_flag+=("\(--.*\)=")/must_have_one_flag+=("\1")/' \
	-e "s/${LWORD}_filedir${RWORD}/__ark_filedir/g" \
	-e "s/${LWORD}_get_comp_words_by_ref${RWORD}/__ark_get_comp_words_by_ref/g" \
	-e "s/${LWORD}__ltrim_colon_completions${RWORD}/__ark_ltrim_colon_completions/g" \
	-e "s/${LWORD}compgen${RWORD}/__ark_compgen/g" \
	-e "s/${LWORD}compopt${RWORD}/__ark_compopt/g" \
	-e "s/${LWORD}declare${RWORD}/builtin declare/g" \
	-e "s/\\\$(type${RWORD}/\$(__ark_type/g" \
	<<'BASH_COMPLETION_EOF'
# bash completion for ark                                  -*- shell-script -*-

__debug()
{
    if [[ -n ${BASH_COMP_DEBUG_FILE} ]]; then
        echo "$*" >> "${BASH_COMP_DEBUG_FILE}"
    fi
}

# Homebrew on Macs have version 1.3 of bash-completion which doesn't include
# _init_completion. This is a very minimal version of that function.
__my_init_completion()
{
    COMPREPLY=()
    _get_comp_words_by_ref "$@" cur prev words cword
}

__index_of_word()
{
    local w word=$1
    shift
    index=0
    for w in "$@"; do
        [[ $w = "$word" ]] && return
        index=$((index+1))
    done
    index=-1
}

__contains_word()
{
    local w word=$1; shift
    for w in "$@"; do
        [[ $w = "$word" ]] && return
    done
    return 1
}

__handle_reply()
{
    __debug "${FUNCNAME[0]}"
    case $cur in
        -*)
            if [[ $(type -t compopt) = "builtin" ]]; then
                compopt -o nospace
            fi
            local allflags
            if [ ${#must_have_one_flag[@]} -ne 0 ]; then
                allflags=("${must_have_one_flag[@]}")
            else
                allflags=("${flags[*]} ${two_word_flags[*]}")
            fi
            COMPREPLY=( $(compgen -W "${allflags[*]}" -- "$cur") )
            if [[ $(type -t compopt) = "builtin" ]]; then
                [[ "${COMPREPLY[0]}" == *= ]] || compopt +o nospace
            fi

            # complete after --flag=abc
            if [[ $cur == *=* ]]; then
                if [[ $(type -t compopt) = "builtin" ]]; then
                    compopt +o nospace
                fi

                local index flag
                flag="${cur%%=*}"
                __index_of_word "${flag}" "${flags_with_completion[@]}"
                COMPREPLY=()
                if [[ ${index} -ge 0 ]]; then
                    PREFIX=""
                    cur="${cur#*=}"
                    ${flags_completion[${index}]}
                    if [ -n "${ZSH_VERSION}" ]; then
                        # zfs completion needs --flag= prefix
                        eval "COMPREPLY=( \"\${COMPREPLY[@]/#/${flag}=}\" )"
                    fi
                fi
            fi
            return 0;
            ;;
    esac

    # check if we are handling a flag with special work handling
    local index
    __index_of_word "${prev}" "${flags_with_completion[@]}"
    if [[ ${index} -ge 0 ]]; then
        ${flags_completion[${index}]}
        return
    fi

    # we are parsing a flag and don't have a special handler, no completion
    if [[ ${cur} != "${words[cword]}" ]]; then
        return
    fi

    local completions
    completions=("${commands[@]}")
    if [[ ${#must_have_one_noun[@]} -ne 0 ]]; then
        completions=("${must_have_one_noun[@]}")
    fi
    if [[ ${#must_have_one_flag[@]} -ne 0 ]]; then
        completions+=("${must_have_one_flag[@]}")
    fi
    COMPREPLY=( $(compgen -W "${completions[*]}" -- "$cur") )

    if [[ ${#COMPREPLY[@]} -eq 0 && ${#noun_aliases[@]} -gt 0 && ${#must_have_one_noun[@]} -ne 0 ]]; then
        COMPREPLY=( $(compgen -W "${noun_aliases[*]}" -- "$cur") )
    fi

    if [[ ${#COMPREPLY[@]} -eq 0 ]]; then
        declare -F __custom_func >/dev/null && __custom_func
    fi

    # available in bash-completion >= 2, not always present on macOS
    if declare -F __ltrim_colon_completions >/dev/null; then
        __ltrim_colon_completions "$cur"
    fi
}

# The arguments should be in the form "ext1|ext2|extn"
__handle_filename_extension_flag()
{
    local ext="$1"
    _filedir "@(${ext})"
}

__handle_subdirs_in_dir_flag()
{
    local dir="$1"
    pushd "${dir}" >/dev/null 2>&1 && _filedir -d && popd >/dev/null 2>&1
}

__handle_flag()
{
    __debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"

    # if a command required a flag, and we found it, unset must_have_one_flag()
    local flagname=${words[c]}
    local flagvalue
    # if the word contained an =
    if [[ ${words[c]} == *"="* ]]; then
        flagvalue=${flagname#*=} # take in as flagvalue after the =
        flagname=${flagname%%=*} # strip everything after the =
        flagname="${flagname}=" # but put the = back
    fi
    __debug "${FUNCNAME[0]}: looking for ${flagname}"
    if __contains_word "${flagname}" "${must_have_one_flag[@]}"; then
        must_have_one_flag=()
    fi

    # if you set a flag which only applies to this command, don't show subcommands
    if __contains_word "${flagname}" "${local_nonpersistent_flags[@]}"; then
      commands=()
    fi

    # keep flag value with flagname as flaghash
    if [ -n "${flagvalue}" ] ; then
        flaghash[${flagname}]=${flagvalue}
    elif [ -n "${words[ $((c+1)) ]}" ] ; then
        flaghash[${flagname}]=${words[ $((c+1)) ]}
    else
        flaghash[${flagname}]="true" # pad "true" for bool flag
    fi

    # skip the argument to a two word flag
    if __contains_word "${words[c]}" "${two_word_flags[@]}"; then
        c=$((c+1))
        # if we are looking for a flags value, don't show commands
        if [[ $c -eq $cword ]]; then
            commands=()
        fi
    fi

    c=$((c+1))

}

__handle_noun()
{
    __debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"

    if __contains_word "${words[c]}" "${must_have_one_noun[@]}"; then
        must_have_one_noun=()
    elif __contains_word "${words[c]}" "${noun_aliases[@]}"; then
        must_have_one_noun=()
    fi

    nouns+=("${words[c]}")
    c=$((c+1))
}

__handle_command()
{
    __debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"

    local next_command
    if [[ -n ${last_command} ]]; then
        next_command="_${last_command}_${words[c]//:/__}"
    else
        if [[ $c -eq 0 ]]; then
            next_command="_$(basename "${words[c]//:/__}")"
        else
            next_command="_${words[c]//:/__}"
        fi
    fi
    c=$((c+1))
    __debug "${FUNCNAME[0]}: looking for ${next_command}"
    declare -F "$next_command" >/dev/null && $next_command
}

__handle_word()
{
    if [[ $c -ge $cword ]]; then
        __handle_reply
        return
    fi
    __debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"
    if [[ "${words[c]}" == -* ]]; then
        __handle_flag
    elif __contains_word "${words[c]}" "${commands[@]}"; then
        __handle_command
    elif [[ $c -eq 0 ]] && __contains_word "$(basename "${words[c]}")" "${commands[@]}"; then
        __handle_command
    else
        __handle_noun
    fi
    __handle_word
}

_ark_backup_create()
{
    last_command="ark_backup_create"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--exclude-namespaces=")
    local_nonpersistent_flags+=("--exclude-namespaces=")
    flags+=("--exclude-resources=")
    local_nonpersistent_flags+=("--exclude-resources=")
    flags+=("--include-cluster-resources")
    local_nonpersistent_flags+=("--include-cluster-resources")
    flags+=("--include-namespaces=")
    local_nonpersistent_flags+=("--include-namespaces=")
    flags+=("--include-resources=")
    local_nonpersistent_flags+=("--include-resources=")
    flags+=("--label-columns=")
    local_nonpersistent_flags+=("--label-columns=")
    flags+=("--labels=")
    local_nonpersistent_flags+=("--labels=")
    flags+=("--output=")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output=")
    flags+=("--selector=")
    two_word_flags+=("-l")
    local_nonpersistent_flags+=("--selector=")
    flags+=("--show-labels")
    local_nonpersistent_flags+=("--show-labels")
    flags+=("--snapshot-volumes")
    local_nonpersistent_flags+=("--snapshot-volumes")
    flags+=("--ttl=")
    local_nonpersistent_flags+=("--ttl=")
    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_backup_delete()
{
    last_command="ark_backup_delete"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--confirm")
    local_nonpersistent_flags+=("--confirm")
    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_backup_describe()
{
    last_command="ark_backup_describe"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--selector=")
    two_word_flags+=("-l")
    local_nonpersistent_flags+=("--selector=")
    flags+=("--volume-details")
    local_nonpersistent_flags+=("--volume-details")
    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_backup_download()
{
    last_command="ark_backup_download"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--force")
    local_nonpersistent_flags+=("--force")
    flags+=("--output=")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output=")
    flags+=("--timeout=")
    local_nonpersistent_flags+=("--timeout=")
    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_backup_get()
{
    last_command="ark_backup_get"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--label-columns=")
    local_nonpersistent_flags+=("--label-columns=")
    flags+=("--output=")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output=")
    flags+=("--selector=")
    two_word_flags+=("-l")
    local_nonpersistent_flags+=("--selector=")
    flags+=("--show-labels")
    local_nonpersistent_flags+=("--show-labels")
    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_backup_logs()
{
    last_command="ark_backup_logs"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--timeout=")
    local_nonpersistent_flags+=("--timeout=")
    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_backup()
{
    last_command="ark_backup"
    commands=()
    commands+=("create")
    commands+=("delete")
    commands+=("describe")
    commands+=("download")
    commands+=("get")
    commands+=("logs")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_client_config_get()
{
    last_command="ark_client_config_get"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_client_config_set()
{
    last_command="ark_client_config_set"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_client_config()
{
    last_command="ark_client_config"
    commands=()
    commands+=("get")
    commands+=("set")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_client()
{
    last_command="ark_client"
    commands=()
    commands+=("config")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_completion()
{
    last_command="ark_completion"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--help")
    flags+=("-h")
    local_nonpersistent_flags+=("--help")
    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    must_have_one_noun+=("bash")
    must_have_one_noun+=("zsh")
    noun_aliases=()
}

_ark_create_backup()
{
    last_command="ark_create_backup"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--exclude-namespaces=")
    local_nonpersistent_flags+=("--exclude-namespaces=")
    flags+=("--exclude-resources=")
    local_nonpersistent_flags+=("--exclude-resources=")
    flags+=("--include-cluster-resources")
    local_nonpersistent_flags+=("--include-cluster-resources")
    flags+=("--include-namespaces=")
    local_nonpersistent_flags+=("--include-namespaces=")
    flags+=("--include-resources=")
    local_nonpersistent_flags+=("--include-resources=")
    flags+=("--label-columns=")
    local_nonpersistent_flags+=("--label-columns=")
    flags+=("--labels=")
    local_nonpersistent_flags+=("--labels=")
    flags+=("--output=")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output=")
    flags+=("--selector=")
    two_word_flags+=("-l")
    local_nonpersistent_flags+=("--selector=")
    flags+=("--show-labels")
    local_nonpersistent_flags+=("--show-labels")
    flags+=("--snapshot-volumes")
    local_nonpersistent_flags+=("--snapshot-volumes")
    flags+=("--ttl=")
    local_nonpersistent_flags+=("--ttl=")
    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_create_restore()
{
    last_command="ark_create_restore"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--exclude-namespaces=")
    local_nonpersistent_flags+=("--exclude-namespaces=")
    flags+=("--exclude-resources=")
    local_nonpersistent_flags+=("--exclude-resources=")
    flags+=("--from-backup=")
    local_nonpersistent_flags+=("--from-backup=")
    flags+=("--include-cluster-resources")
    local_nonpersistent_flags+=("--include-cluster-resources")
    flags+=("--include-namespaces=")
    local_nonpersistent_flags+=("--include-namespaces=")
    flags+=("--include-resources=")
    local_nonpersistent_flags+=("--include-resources=")
    flags+=("--label-columns=")
    local_nonpersistent_flags+=("--label-columns=")
    flags+=("--labels=")
    local_nonpersistent_flags+=("--labels=")
    flags+=("--namespace-mappings=")
    local_nonpersistent_flags+=("--namespace-mappings=")
    flags+=("--output=")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output=")
    flags+=("--restore-volumes")
    local_nonpersistent_flags+=("--restore-volumes")
    flags+=("--selector=")
    two_word_flags+=("-l")
    local_nonpersistent_flags+=("--selector=")
    flags+=("--show-labels")
    local_nonpersistent_flags+=("--show-labels")
    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_create_schedule()
{
    last_command="ark_create_schedule"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--exclude-namespaces=")
    local_nonpersistent_flags+=("--exclude-namespaces=")
    flags+=("--exclude-resources=")
    local_nonpersistent_flags+=("--exclude-resources=")
    flags+=("--include-cluster-resources")
    local_nonpersistent_flags+=("--include-cluster-resources")
    flags+=("--include-namespaces=")
    local_nonpersistent_flags+=("--include-namespaces=")
    flags+=("--include-resources=")
    local_nonpersistent_flags+=("--include-resources=")
    flags+=("--label-columns=")
    local_nonpersistent_flags+=("--label-columns=")
    flags+=("--labels=")
    local_nonpersistent_flags+=("--labels=")
    flags+=("--output=")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output=")
    flags+=("--schedule=")
    local_nonpersistent_flags+=("--schedule=")
    flags+=("--selector=")
    two_word_flags+=("-l")
    local_nonpersistent_flags+=("--selector=")
    flags+=("--show-labels")
    local_nonpersistent_flags+=("--show-labels")
    flags+=("--snapshot-volumes")
    local_nonpersistent_flags+=("--snapshot-volumes")
    flags+=("--ttl=")
    local_nonpersistent_flags+=("--ttl=")
    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_create()
{
    last_command="ark_create"
    commands=()
    commands+=("backup")
    commands+=("restore")
    commands+=("schedule")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_delete_backup()
{
    last_command="ark_delete_backup"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--confirm")
    local_nonpersistent_flags+=("--confirm")
    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_delete_restore()
{
    last_command="ark_delete_restore"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_delete_schedule()
{
    last_command="ark_delete_schedule"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_delete()
{
    last_command="ark_delete"
    commands=()
    commands+=("backup")
    commands+=("restore")
    commands+=("schedule")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_describe_backups()
{
    last_command="ark_describe_backups"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--selector=")
    two_word_flags+=("-l")
    local_nonpersistent_flags+=("--selector=")
    flags+=("--volume-details")
    local_nonpersistent_flags+=("--volume-details")
    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_describe_restores()
{
    last_command="ark_describe_restores"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--selector=")
    two_word_flags+=("-l")
    local_nonpersistent_flags+=("--selector=")
    flags+=("--volume-details")
    local_nonpersistent_flags+=("--volume-details")
    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_describe_schedules()
{
    last_command="ark_describe_schedules"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--selector=")
    two_word_flags+=("-l")
    local_nonpersistent_flags+=("--selector=")
    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_describe()
{
    last_command="ark_describe"
    commands=()
    commands+=("backups")
    commands+=("restores")
    commands+=("schedules")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_get_backups()
{
    last_command="ark_get_backups"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--label-columns=")
    local_nonpersistent_flags+=("--label-columns=")
    flags+=("--output=")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output=")
    flags+=("--selector=")
    two_word_flags+=("-l")
    local_nonpersistent_flags+=("--selector=")
    flags+=("--show-labels")
    local_nonpersistent_flags+=("--show-labels")
    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_get_restores()
{
    last_command="ark_get_restores"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--label-columns=")
    local_nonpersistent_flags+=("--label-columns=")
    flags+=("--output=")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output=")
    flags+=("--selector=")
    two_word_flags+=("-l")
    local_nonpersistent_flags+=("--selector=")
    flags+=("--show-labels")
    local_nonpersistent_flags+=("--show-labels")
    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_get_schedules()
{
    last_command="ark_get_schedules"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--label-columns=")
    local_nonpersistent_flags+=("--label-columns=")
    flags+=("--output=")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output=")
    flags+=("--selector=")
    two_word_flags+=("-l")
    local_nonpersistent_flags+=("--selector=")
    flags+=("--show-labels")
    local_nonpersistent_flags+=("--show-labels")
    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_get()
{
    last_command="ark_get"
    commands=()
    commands+=("backups")
    commands+=("restores")
    commands+=("schedules")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_plugin_add()
{
    last_command="ark_plugin_add"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--image-pull-policy=")
    local_nonpersistent_flags+=("--image-pull-policy=")
    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_plugin_remove()
{
    last_command="ark_plugin_remove"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_plugin()
{
    last_command="ark_plugin"
    commands=()
    commands+=("add")
    commands+=("remove")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_restic_repo_get()
{
    last_command="ark_restic_repo_get"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--label-columns=")
    local_nonpersistent_flags+=("--label-columns=")
    flags+=("--output=")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output=")
    flags+=("--selector=")
    two_word_flags+=("-l")
    local_nonpersistent_flags+=("--selector=")
    flags+=("--show-labels")
    local_nonpersistent_flags+=("--show-labels")
    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_restic_repo()
{
    last_command="ark_restic_repo"
    commands=()
    commands+=("get")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_restic_server()
{
    last_command="ark_restic_server"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--log-level=")
    local_nonpersistent_flags+=("--log-level=")
    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_restic()
{
    last_command="ark_restic"
    commands=()
    commands+=("repo")
    commands+=("server")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_restore_create()
{
    last_command="ark_restore_create"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--exclude-namespaces=")
    local_nonpersistent_flags+=("--exclude-namespaces=")
    flags+=("--exclude-resources=")
    local_nonpersistent_flags+=("--exclude-resources=")
    flags+=("--from-backup=")
    local_nonpersistent_flags+=("--from-backup=")
    flags+=("--include-cluster-resources")
    local_nonpersistent_flags+=("--include-cluster-resources")
    flags+=("--include-namespaces=")
    local_nonpersistent_flags+=("--include-namespaces=")
    flags+=("--include-resources=")
    local_nonpersistent_flags+=("--include-resources=")
    flags+=("--label-columns=")
    local_nonpersistent_flags+=("--label-columns=")
    flags+=("--labels=")
    local_nonpersistent_flags+=("--labels=")
    flags+=("--namespace-mappings=")
    local_nonpersistent_flags+=("--namespace-mappings=")
    flags+=("--output=")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output=")
    flags+=("--restore-volumes")
    local_nonpersistent_flags+=("--restore-volumes")
    flags+=("--selector=")
    two_word_flags+=("-l")
    local_nonpersistent_flags+=("--selector=")
    flags+=("--show-labels")
    local_nonpersistent_flags+=("--show-labels")
    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_restore_delete()
{
    last_command="ark_restore_delete"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_restore_describe()
{
    last_command="ark_restore_describe"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--selector=")
    two_word_flags+=("-l")
    local_nonpersistent_flags+=("--selector=")
    flags+=("--volume-details")
    local_nonpersistent_flags+=("--volume-details")
    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_restore_get()
{
    last_command="ark_restore_get"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--label-columns=")
    local_nonpersistent_flags+=("--label-columns=")
    flags+=("--output=")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output=")
    flags+=("--selector=")
    two_word_flags+=("-l")
    local_nonpersistent_flags+=("--selector=")
    flags+=("--show-labels")
    local_nonpersistent_flags+=("--show-labels")
    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_restore_logs()
{
    last_command="ark_restore_logs"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--timeout=")
    local_nonpersistent_flags+=("--timeout=")
    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_restore()
{
    last_command="ark_restore"
    commands=()
    commands+=("create")
    commands+=("delete")
    commands+=("describe")
    commands+=("get")
    commands+=("logs")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_schedule_create()
{
    last_command="ark_schedule_create"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--exclude-namespaces=")
    local_nonpersistent_flags+=("--exclude-namespaces=")
    flags+=("--exclude-resources=")
    local_nonpersistent_flags+=("--exclude-resources=")
    flags+=("--include-cluster-resources")
    local_nonpersistent_flags+=("--include-cluster-resources")
    flags+=("--include-namespaces=")
    local_nonpersistent_flags+=("--include-namespaces=")
    flags+=("--include-resources=")
    local_nonpersistent_flags+=("--include-resources=")
    flags+=("--label-columns=")
    local_nonpersistent_flags+=("--label-columns=")
    flags+=("--labels=")
    local_nonpersistent_flags+=("--labels=")
    flags+=("--output=")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output=")
    flags+=("--schedule=")
    local_nonpersistent_flags+=("--schedule=")
    flags+=("--selector=")
    two_word_flags+=("-l")
    local_nonpersistent_flags+=("--selector=")
    flags+=("--show-labels")
    local_nonpersistent_flags+=("--show-labels")
    flags+=("--snapshot-volumes")
    local_nonpersistent_flags+=("--snapshot-volumes")
    flags+=("--ttl=")
    local_nonpersistent_flags+=("--ttl=")
    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_schedule_delete()
{
    last_command="ark_schedule_delete"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_schedule_describe()
{
    last_command="ark_schedule_describe"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--selector=")
    two_word_flags+=("-l")
    local_nonpersistent_flags+=("--selector=")
    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_schedule_get()
{
    last_command="ark_schedule_get"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--label-columns=")
    local_nonpersistent_flags+=("--label-columns=")
    flags+=("--output=")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output=")
    flags+=("--selector=")
    two_word_flags+=("-l")
    local_nonpersistent_flags+=("--selector=")
    flags+=("--show-labels")
    local_nonpersistent_flags+=("--show-labels")
    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_schedule()
{
    last_command="ark_schedule"
    commands=()
    commands+=("create")
    commands+=("delete")
    commands+=("describe")
    commands+=("get")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_server()
{
    last_command="ark_server"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--log-level=")
    local_nonpersistent_flags+=("--log-level=")
    flags+=("--metrics-address=")
    local_nonpersistent_flags+=("--metrics-address=")
    flags+=("--plugin-dir=")
    local_nonpersistent_flags+=("--plugin-dir=")
    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark_version()
{
    last_command="ark_version"
    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_ark()
{
    last_command="ark"
    commands=()
    commands+=("backup")
    commands+=("client")
    commands+=("completion")
    commands+=("create")
    commands+=("delete")
    commands+=("describe")
    commands+=("get")
    commands+=("plugin")
    commands+=("restic")
    commands+=("restore")
    commands+=("schedule")
    commands+=("server")
    commands+=("version")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--alsologtostderr")
    flags+=("--kubeconfig=")
    flags+=("--kubecontext=")
    flags+=("--log_backtrace_at=")
    flags+=("--log_dir=")
    flags+=("--logtostderr")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--stderrthreshold=")
    flags+=("--v=")
    two_word_flags+=("-v")
    flags+=("--vmodule=")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

__start_ark()
{
    local cur prev words cword
    declare -A flaghash 2>/dev/null || :
    if declare -F _init_completion >/dev/null 2>&1; then
        _init_completion -s || return
    else
        __my_init_completion -n "=" || return
    fi

    local c=0
    local flags=()
    local two_word_flags=()
    local local_nonpersistent_flags=()
    local flags_with_completion=()
    local flags_completion=()
    local commands=("ark")
    local must_have_one_flag=()
    local must_have_one_noun=()
    local last_command
    local nouns=()

    __handle_word
}

if [[ $(type -t compopt) = "builtin" ]]; then
    complete -o default -F __start_ark ark
else
    complete -o default -o nospace -F __start_ark ark
fi

# ex: ts=4 sw=4 et filetype=sh

BASH_COMPLETION_EOF
}
__ark_bash_source <(__ark_convert_bash_to_zsh)
_complete ark 2>/dev/null
