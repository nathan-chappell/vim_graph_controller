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

let b:graph_file = '.graph.dot'
let b:tmp_file = '.graph.dot.tmp'

let s:empty_graph = 'digraph { graph [ layout = dot, rankdir=LR ] }'

function! UpdateGraph(gvpr_cmd)
  silent execute '! gvpr ''' . a:gvpr_cmd . ''' ' . b:graph_file . ' > ' . b:tmp_file
  silent execute '! cat ' . b:tmp_file . ' > ' . b:graph_file
endfunction

function! GetGraphInfo(gvpr_cmd)
  silent execute '! gvpr ''' . a:gvpr_cmd . ''' ' . b:graph_file . ' > ' . b:tmp_file
  let l:result = get(readfile(b:tmp_file), 0)
  return l:result
endfunction

function! InitGraph()
  echom 'initializing graph for: ' . expand('%')
  silent execute '! echo ''' . s:empty_graph . ''' > ' . b:graph_file
  silent execute '! dot -Txlib ' . b:graph_file '. &'
endfunction

function! GetSelectedNode()
  let l:gvpr_cmd = 'N [aget($,"selected") == "true"] { printf("\%s\n", name) }'
  return GetGraphInfo(l:gvpr_cmd)
endfunction

function! SelectNode(label)
  echo 'SelectNode'
  execute 'echom "selecting node: ' . a:label . '"'
  let l:gvpr_cmd = 
  \'N [name == "' . a:label . '"] { ' .
    \'aset($,"selected","true"); ' .
    \'aset($,"penwidth",3.0); ' .
  \'}' .
  \'N [name \!= "' . a:label . '"] { ' .
    \'aset($,"selected","false"); ' .
    \'aset($,"penwidth",1.0); ' .
  \'}' .
  \'N [] E []'
  call UpdateGraph(l:gvpr_cmd)
endfunction

function! AddNode(label, command)
  let l:gvpr_cmd = 
  \'BEG_G {' .
  \'  node_t new_node = node($, "' . a:label . '");' .
  \'  aset(new_node,"command","'. a:command . '");' .
  \'}' .
  \'N [] E []'
  call UpdateGraph(l:gvpr_cmd)
  let l:cur_node = GetSelectedNode()
  if type(l:cur_node) == 1
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

function! PrintChildren()
  let selected_node = GetSelectedNode()
  if type(l:selected_node) == 1
    let l:gvpr_cmd = 
      \'BEG_G { node_t selected_node = node($,"' . l:selected_node . '") }' .
      \'E [tail == selected_node] { printf("\%s\n", head.name) }'
    call GetGraphInfo(l:gvpr_cmd)
  endif
endfunction

function! PrintParent()
  let selected_node = GetSelectedNode()
  if type(l:selected_node) == 1
    let l:gvpr_cmd = 
      \'BEG_G { node_t selected_node = node($,"' . l:selected_node . '") }' .
      \'E [head == selected_node] { printf("\%s\n", tail.name) }'
    call GetGraphInfo(l:gvpr_cmd)
  endif
endfunction

function! Ascend()
  call PrintParent()
  call SelectNode(get(readfile(b:tmp_file), 0))
endfunction

function! Descend()
  call PrintChildren()
  call SelectNode(get(readfile(b:tmp_file), 0))
endfunction

function! Test()
  echom 'beginning test'
  call InitGraph()
  call AddNode('one', 'foobar')
  call AddNode('two', 'foobar2')
  call Ascend()
  call AddNode('three', 'foobar3')
  call Ascend()
  echom GetSelectedNode()
  sleep 1
  call Descend()
  redraw!
endfunction!

function! Foo(str)
  execute 'echo "' . a:str[0] . '"'
  return "gay"
endfunction

function! Bar(str)
  return Foo(a:str)
endfunction
