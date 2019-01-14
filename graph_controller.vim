"This vimscript gives the vim user the ability to control a graph.  This graph
"shall consists of nodes and edges.  The graph will be a tree, which puts
"considerable constraints on the edges, but there is no pre-conceived semantics
"for the edges, although, some sort of "child/ancestor" relation seems quite
"natural.  The nodes maintain a vim command to execute.  This command which will
"be summoned when the node is selected.  With system commands, this means
"selecting node can do anything.  This is a "generalization" of a concept that
"comes from "tag" files, where they maintain a command to find a specific tag.
"
"The motivation for the project is to create a way to author one's own means of
"understanding text.  This may best be described with an example.  Say you are
"tasked with manipulating a large program.  It may be beneficial to understand
"the way the program works before you start chopping up the code.  Vim offers an
"incredibly useful way to browse through a program by using tag files.  The power
"of this method of traversal has one limitation, in that it does not maintain the
"traveler's "context," i.e. where you are in a program relative to your history.
"
"Suppose as you are going from place to place you find an important snippet of
"code that is related to some feature you are trying to comprehend.  It may be
"nice to "bookmark" this location, and come back to it later.  Vim's "marks" can
"do this for you.  With marks, you can look at what marks you currently have with
"the command :marks, but unfortunately it is not so easy to identify what each
"mark means, how they are related to one another, and there are only so many
"marks you can technically have.
"
"Say instead of using a mark, you push a node onto your graph with the command to
"move to your current location.  You can give it a meaningful label, and add it
"to a subgraph.  That subgraph may denote the file to which the location belongs
"or maybe a "feature" that the code applies to.  The point is that the node can
"be placed as a descendent of a node, indicating some hierarchical relationship
"and can be a member of a subgraph, indicating some other meaningful semantics.

"The graph and all relevant information is stored in $graph_file.  The $tmp_file
"is necessary because gvpr kills your graph if you try to write to a file you're
"currently trying to read from.

let s:empty_graph = 'digraph { graph [ layout = dot, rankdir=LR ] }'

let s:debug_mode = 't'
let s:log_file = '.graph_controller.log'
call writefile([''], s:log_file)

function! InitLocals()
  let b:graph_file = '.graph.dot'
  let b:tmp_file = '.graph.dot.tmp'
endfunction

function! Log(items)
  call writefile(a:items + [''], s:log_file, 'a')
endfunction

function! LogSystemCmd(cmd)
  let result = systemlist(a:cmd)
  if exists('s:debug_mode')
    call Log(['command: ' . a:cmd])
    call Log(l:result)
  endif
  return l:result
endfunction

function! UpdateGraph(gvpr_cmd)
  let l:new_graph = LogSystemCmd("gvpr -q '" . a:gvpr_cmd . "' " . b:graph_file)
  if !v:shell_error
    call writefile(l:new_graph, b:graph_file)
  elseif
    Log(['gvpr error:', string(v:shell_error)])
  endif
endfunction

function! GetGraphInfo(gvpr_cmd)
  return LogSystemCmd("gvpr -q '" . a:gvpr_cmd . "' " . b:graph_file)
endfunction

function! OpenGraph()
  "for some reason system() doesn't want to keep the thing open...
  silent execute '! dot -Txlib ' . b:graph_file '. &'
  redraw!
endfunction

function! InitGraph()
  call Log(['initializing graph for: ' . expand('%')])
  call writefile([s:empty_graph], b:graph_file)
endfunction

function! GetSelectedNode()
  let l:gvpr_cmd = 
    \'gvpr -q ''N [selected == "true"] { printf(name) } '' ' . b:graph_file
  return get(LogSystemCmd(l:gvpr_cmd), 0, -1)
endfunction

let s:location_attributes = [["shape","rectangle"],["color","blue"]]

function! SetAttributes(label, attributes)
  if empty(a:attributes) | return | endif
  call Log(['setting attributes: ' . a:label . ' - ' . string(a:attributes)])
  let l:gvpr_cmd = 
    \'BEG_G {'
      \'node_t n = node($,'. a:label . ');' .
      join(map
          (deepcopy(a:attributes),
          '"aset(n,\"" . v:val[0] . "\",\"" . v:val[1] . "\");"')) .
    \'}' .
    \'N [] E []'
  call UpdateGraph(l:gvpr_cmd)
endfunction

function! SelectNode(label)
  let l:gvpr_cmd = 
  \'N [name == "' . a:label . '"] { ' .
    \'aset($,"selected","true"); ' .
    \'aset($,"penwidth",3.0); ' .
  \'}' .
  \'N [name != "' . a:label . '"] { ' .
    \'aset($,"selected","false"); ' .
    \'aset($,"penwidth",1.0); ' .
  \'}' .
  \'N [] E []'
  call UpdateGraph(l:gvpr_cmd)
endfunction

function! AddNode(label, attributes)
  let l:gvpr_cmd = 
  \'BEG_G {' .
  \'  node_t new_node = node($, "' . a:label . '");' .
      \join(map
          \(deepcopy(a:attributes),
          \'"aset(new_node,\"" . v:val[0] . "\",\"" . v:val[1] . "\");"')) .
  \'}' .
  \'N [] E []'
  call UpdateGraph(l:gvpr_cmd)
  let l:cur_node = GetSelectedNode()
  if l:cur_node != -1
    call AddEdge(l:cur_node, a:label)
  endif
  call SelectNode(a:label)
endfunction

function! AddEdge(tail, head)
  let l:gvpr_cmd =
  \'BEG_G {' .
    \'node_t t = node($,"' . a:tail . '");' .
    \'node_t h = node($,"' . a:head . '");' .
    \'edge_t e = edge(t,h,"' . a:tail . ' -> ' . a:head . '")' .
  \'}' .
  \'N [] E []'
  call UpdateGraph(l:gvpr_cmd)
endfunction

function! MoveTo(gvpr_cmd)
  let move_to = get(readfile(b:tmp_file), 0)
  if type(l:move_to) == 1
    call SelectNode(l:move_to)
  endif
  redraw!
endfunction

function! GetChildren()
  let selected_node = GetSelectedNode()
  if l:selected_node != -1
    let l:gvpr_cmd = 
      \'BEG_G { node_t selected_node = node($,"' . l:selected_node . '") }' .
      \'E [tail == selected_node] { printf("\%s\n", head.name) }'
    return GetGraphInfo(l:gvpr_cmd)
  endif
endfunction

function! GetParent()
  let selected_node = GetSelectedNode()
  if l:selected_node != -1
    let l:gvpr_cmd = 
      \'BEG_G { node_t selected_node = node($,"' . l:selected_node . '") }' .
      \'E [head == selected_node] { printf("\%s\n", tail.name) }'
    return GetGraphInfo(l:gvpr_cmd)
  endif
endfunction

function! GetCommand()
  let selected_node = GetSelectedNode()
  if l:selected_node == -1 | return "" | endif
  let l:gvpr_cmd = 
    \'BEG_G {' .
      \'node_t selected_node = node($,"' . l:selected_node . '"); ' .
      \'printf("\%s\n", aget(selected_node, "command"))' .
    \'}'
  return GetGraphInfo(l:gvpr_cmd)
endfunction

function! Ascend()
  call SelectNode(GetParent()[0])
endfunction

function! Descend()
  call SelectNode(GetChildren()[0])
endfunction

function! Sibling()
  let selected_node = GetSelectedNode()
  if l:selected_node != -1
    call Ascend()
    let l:children = GetChildren()
    let idx = index(l:children, l:selected_node) + 1
    let idx = l:idx % len(l:children)
    call SelectNode(get(l:children, l:idx, ""))
  endif
  redraw!
endfunction

function! PushLocation()
  let label = input("enter location name: ")
  let cmd = 'view ' . expand("%:p") . ' | call setpos(\".\",' . string(getcurpos()) . ')'
  call AddNode(l:label, s:location_attributes)
  call AddCommand(l:label,l:cmd)
endfunction

"not safe... change 'command attribute' to 'command list'
function! AddCommand(label, cmd)
  "let new_cmd = string(GetCommand() + [a:cmd])
  let new_cmd = GetCommand() . ' | ' . cmd
  "echom string(GetCommands())
  "echom l:new_cmd
  call SetAttributes(a:label, ['command', l:new_cmd])
endfunction

function! PushCommand()
  let new_cmd = input("enter command to add to node: ")
  let node = GetSelectedNode()
  if !empty(l:node) | AddCommand(l:node, l:new_cmd) | endif
endfunction

function! ExecuteSelected()
  for cmd in GetCommands()
    execute cmd
  redraw!
endfunction

function! Test()
  call Log(['beginning test'])
  call InitGraph()
  call OpenGraph()
  "call AddNode('one', [['command',':192'],['shape','square']])
  "call AddNode('two', [['command',':' . line("'s")],['color','green']])
  "call ExecuteSelected()
  "call Ascend()
  "call AddNode('three', [['command',':echo ''foobar'''],['peripheries','3']])
  "call Sibling()
  "call Sibling()
  "call Ascend()
endfunction!

"mappings
nnoremap <leader>gi :call InitGraph()
nnoremap <leader>go :call OpenGraph()
nnoremap <leader>ga :call Ascend()
nnoremap <leader>gd :call Descend()
nnoremap <leader>gs :call Sibling()
nnoremap <leader>ge :call ExecuteSelected()
nnoremap <leader>gp :call PushLocation()

function! Foo(str)
  if !len(a:str) | return | endif
  echo 'bar'
endfunction

function! Bar(str)
  return Foo(a:str)
endfunction
