% Copyright 2012, Dell 
% 
% Licensed under the Apache License, Version 2.0 (the "License"); 
% you may not use this file except in compliance with the License. 
% You may obtain a copy of the License at 
% 
%  http://www.apache.org/licenses/LICENSE-2.0 
% 
% Unless required by applicable law or agreed to in writing, software 
% distributed under the License is distributed on an "AS IS" BASIS, 
% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. 
% See the License for the specific language governing permissions and 
% limitations under the License. 
% 
-module(eurl).
-export([post/3, put/3, delete/2, delete/3, delete/4, post_params/1, post/5, put_post/4, put_post/5, uri/2, path/1, path/2]).
-export([get/2, get/3, get_page/3, get_ajax/2, peek/2, search/2, search/3]).
-export([find_button/2, find_link/2, find_block/4, find_block/5, find_form/2, find_div/2, html_body/1, html_head/1, find_heading/2]).
-export([form_submit/2, form_fields_merge/2]).
-export([encode/1]).

search(Match, Results, Test) ->
	F = fun(X) -> case {X, Test} of 
	  {true, true} -> true; 
	  {true, false} -> false;
	  {_, false} -> true;
	  {_, true} -> false end end,
	lists:any(F, ([peek(Match,Result) || Result <- Results, Result =/= [no_op]])).
search(Match, Results) ->
	search(Match, Results, true).

html_peek({Code, Input}, RegEx) ->
  bdd_utils:log(warn, "eurl:html_peek looking for RegEx ~p with code ~p did not get searchable input from ~p",[RegEx, Code, Input]),
  false;
html_peek(Input, RegEx) ->
	{ok, RE} = re:compile(RegEx, [caseless, multiline, dotall, {newline , anycrlf}]),
	Result = re:run(Input, RE),
	bdd_utils:log(trace, "eurl:html_peek compile ~p match: ~p", [RegEx, Result]),
	case Result of
		{match, [_A, _B, _C, _D, {Start, Length} | _Tail ]} -> string:substr(Input, Start-5, Length+13);
		_ -> false
	end.
  
html_body(Input) ->
  RegEx = "<(html|HTML)(.*)<(body|BODY)>(.*)</(body|BODY)>(.*)</(html|HTML)>",
  html_peek(Input, RegEx).
  
html_head(Input) ->
  RegEx = "<(html|HTML)(.*)<(head|HEAD)>(.*)</(head|HEAD)>(.*)</(html|HTML)>",
  html_peek(Input, RegEx).

peek(Match, {ajax, 200, Input}) -> peek(Match, Input);  
peek(Match, {Code, Input})      -> 
  bdd_utils:log(warn, "eurl:peek looking for RegEx ~p with code ~p did not get searchable input from ~p",[Match, Code, Input]),
  false;
peek(Match, Input) ->
	bdd_utils:log(trace, "eurl:peek compile looking for: ~p", [Match]),
	try re:compile(Match, [caseless, multiline, dotall, {newline , anycrlf}]) of
	  {ok, RE} ->
    	try re:run(Input, RE) of
    		{match, R1} -> 	bdd_utils:log(debug, "eurl:peek match for ~p result: ~p", [Match, R1]), true;
    		nomatch ->      bdd_utils:log(debug, "eurl:peek did NOT find match for ~p", [Match]), false;
    		R2 ->           bdd_utils:log(debug, "eurl:peek RegEx unexpected run result of ~p shows peek did NOT match ~p", [R2, Match]), false
    	catch
    	  E2 -> bdd_utils:log(error, "eurl:peek RegEx error (~p) Could not parse regex ~p for ~p",[E2, Match]), 
    	        false
    	end;
    X -> bdd_utils:log(error, "eurl:peek RegEx compile returned ~p. Could not compile regex ~p",[X, Match]), 
	       false
  catch
    E1 -> bdd_utils:log(error, "eurl:peek RegEx error (~p) Could not parse regex ~p",[E1, Match]), 
    	    false
  end.  
	
	
find_button(Match, Input) ->
	Form = find_block("<form ", "</form>", Input, "value='"++Match++"'"),
	Button = find_block("<input ", ">", Form,  "value='"++Match++"'"),
	{ok, RegEx} = re:compile("type='submit'"),
	case re:run(Button, RegEx) of
	  {match, _} -> Button;
	  _ -> bdd_utils:log(error, "eurl:find_button Could not find button with value  '~p'.  HTML could have other components encoded in a tag.", [Match]), "BUTTON NOT FOUND"
	end.
	
% return the HREF part of an anchor tag given the content of the link
find_link(Match, {Code, Info}) ->
  bdd_utils:log(warn, "eurl:find_link Attempting to find match ~p but input was ~p with ~p", [Match, Code, Info]),
  {error, Code, Info};
find_link(Match, Input) ->
	bdd_utils:log(debug, "eurl:find_link starting to look for ~p", [Match]),
	RegEx = "(\\<(a|A)\\b(/?[^\\>]+)\\>"++Match++"\\<\\/(a|A)\\>)",
	RE = case re:compile(RegEx, [multiline, dotall, {newline , anycrlf}]) of
	  {ok, R} -> R;
	  Error   -> bdd_utils:log(error, "eurl:find_link Could not parse regex '~p' given '~p'", [Error, RegEx]), 
	             throw(eurl_find_link_RegEx_broken)
	end,
	bdd_utils:log(trace, "eurl:find_link looking for ~p in ~p", [Match, Input]),
	AnchorTag = try re:run(Input, RE) of
	  {match, [{AStart, ALength} | _]} -> 
	               string:substr(Input, AStart+1,AStart+ALength);
	  nomatch   -> bdd_utils:log(error, "eurl:find_link AnchorTag Could not find ~p in request  (you may need to escape characters).", [Match]), 
	               "ERROR: Could not find link";
	  REX       -> bdd_utils:log(error, "eurl:find_link AnchorTag Could not find Anchor tags enclosing '~p'.  HTML could have other components encoded in a tag with RegEx ~p", [Match, REX]), 
	               "ERROR: Unexpected RegEx pattern while finding link"
	catch
	   E1       -> bdd_utils:log(error, "eurl:find_link AnchorTag error (~p) Could not parse regex ~p for ~p inside of ~p",[E1, RE, RegEx, Input]), 
	               "ERROR: RegEx throw while looking for link"
	end,
	{ok, HrefREX} = re:compile("\\bhref=(['\"])([^\\s]+?)(\\1)", [multiline, dotall, {newline , anycrlf}]),
  find_link_part2(AnchorTag, HrefREX, Match).

% split find link into 2 parts to that we can stop processing if the 1st RegEx fails
find_link_part2({error, Msg}, HrefREX, _Match) -> {error, Msg, HrefREX};
find_link_part2(AnchorTag, HrefREX, Match)     ->
	try re:run(AnchorTag, HrefREX) of
	  {match, [_1, _2, {HStart, HLength} | _]} -> 
	             Href = string:substr(AnchorTag, HStart+1,HLength),
	  	         bdd_utils:log(trace, "eurl:find_link found anchor ~p in path ~p", [AnchorTag, Href]),
	  	         Href;
	  nomatch -> bdd_utils:log(error, "eurl:find_link Href Could not find ~s in request (you may need to escape characters)", [Match]), 
	             {error, "ERROR: No Href Found", AnchorTag};
	  RE      -> bdd_utils:log(error, "eurl:find_link Href Could not find href= information in substring '~p' with result ~p", [AnchorTag, RE]), 
	             {error, "ERROR: No URL Found", AnchorTag}
	catch
	  E2 ->      bdd_utils:log(error, "eurl:find_link Href error (~p) Could not parse regex ~p for ~p inside of ~p",[E2, HrefREX, Match, AnchorTag]), 
	             {error, "ERROR: No URL Found and throws error", AnchorTag}
	end.

find_heading(Input, Text) ->
  RegEx = "<h[1-9]>"++Text++"</h[1-9]>",
  case re:run(Input, RegEx) of
    nomatch    -> bdd_utils:log(debug, eurl, find_heading, "Did not find heading ~p using RegEx ~p", [Text, RegEx]), false;
    {match, _} -> true
  end.

find_div([], _)       -> not_found;
find_div(Input, Id)   ->
  Start = string:str(Input,"<div"),
  case Start of
    0 -> not_found;
    _ -> Block = string:substr(Input, Start+5),
         Close = string:str(Block,">"),
         Tag = string:substr(Block, 1, Close-1),
         Next = string:substr(Block, Close+1),
         RegEx = "[id|ID]=['|\""++Id++"['|\"]",
         case re:run(Tag, RegEx) of
           {match, _} -> Next;
           nomatch -> find_div(Next, Id)
         end
  end.
  
find_form_inputs(Input) ->
  I = binary_to_list(Input),
	{key_value_extract(I, "name", unknown_name),
	  key_value_extract(I, "value", unknown_value),
	  key_value_extract(I, "id", unknown_id), 
	  key_value_extract(I, "type", unknown_type)}.
  
key_value_extract(Input, Key, Fail) ->
	{ok, Rex} = re:compile("\ "++Key++"=(['\\\"])(.+?)(['\\\"])", [multiline, dotall, {newline , anycrlf}]),
  M = re:run(Input, Rex),
	bdd_utils:log(x, "eurl:find_form_input_extract regex result ~p with ~p",[Input, M]),
	Value = try M of
	  {match, [_, _, {S, L} | _]} when S>0; L>0 -> string:substr(Input, (S+1), L);
	  _ -> Fail
	catch
	  _ -> Fail
	end,
	bdd_utils:log(dump, "eurl:find_form_input_extract exiting find of ~p with ~p",[Key, Value]),
	Value.

find_form(Input, KeyPhrase) ->
  [Form] = find_block("<form","</form>", Input, KeyPhrase), 
  [FormHeadRaw | _ ]= re:split(Form, ">"),
  FormHead = binary_to_list(FormHeadRaw),
  bdd_utils:log(x, "eurl:find_form - raw form ~p",[Form]),
	Href = key_value_extract(FormHead, "action", no_target),
	Method = list_to_atom(string:to_lower(key_value_extract(FormHead, "method", "post"))),
  InputsRaw1 = re:split(Form, "<input "),
  InputsRaw = [ I || [I | _] <- [ re:split(X, "/>") || X <- InputsRaw1]],
	InputsAll = [find_form_inputs(I) || I <- InputsRaw],
	Inputs = lists:dropwhile(fun(X) -> case X of {unknown_name, _, _, _} -> true; _ -> false end end, InputsAll),
  bdd_utils:log(debug, "eurl:find_form - form action ~p parse ~p fields ~p",[Method, Href, Inputs]),
  [{target, Href}, {method, Method}, {fields, Inputs}].


% we allow for a of open tags (nesting) but only the inner close is needed
find_block(OpenTag, CloseTag, Input, Match)         -> find_block(OpenTag, CloseTag, Input, Match, 1000).
find_block(OpenTag, CloseTag, Input, Match, MaxLen) ->
  {ok, RE} = re:compile([Match]),
  CandidatesNotTested = re:split(Input, OpenTag, [{return, list}]),
  Candidates = [ find_block_helper(C, RE) || C <- CandidatesNotTested ],
  Block = case [ C || C <- Candidates, C =/= false ] of
    [B] -> B;
    [B | _] -> B;
    _ -> []
  end,
  case re:split(Block, CloseTag, [{parts, 2}, {return, list}]) of
    [Inside] -> [Inside];
    [Inside | _ ] -> [Inside];
    [] -> [string:substr(Block,0,MaxLen)]  % we need a fall back limit just in case
  end.

find_block_helper(Test, RE) ->
	case re:run(Test, RE) of
		{match, _} -> Test;
		_ -> false
	end.

uri(Config, Path) ->
	Base = bdd_utils:config(Config, url),
	path(Base,Path).

path([Head, Tail])  -> path(Head, Tail);
path([Head | Tail]) -> path(Head, path(Tail)).

path(Base, Path) when is_atom(Path) -> path(Base, atom_to_list(Path));  
path(Base, Path) when is_atom(Base) -> path(atom_to_list(Base), Path); 
path(Base, Path) ->
  case {string:right(Base,1),string:left(Path,1)} of
    {"/", "?"}-> string:substr(length(Base)-1) ++ Path;
    {"/", "/"}-> Base ++ string:substr(Path,2);
    {_, "/"}  -> Base ++ Path;
    {"/", _}  -> Base ++ Path;
    {_, "?"}  -> Base ++ Path;
    {_, _}    -> Base ++ "/" ++ Path
  end.
  
% get a page from a server - returns {Code, Body}
get(Config, Page)             -> get_page(Config, Page, []).
get(Config, Page, ok)         -> get_page(Config, Page, []);
get(Config, Page, not_found)  -> get_page(Config, Page, [{404, not_found}]);
get(Config, URL, all) ->
  bdd_utils:log(Config, debug, "eurl:get Getting ~p", [URL]),
	Result = simple_auth:request(Config, URL),
	{_, {{_HTTP, Code, _CodeWord}, _Header, Body}} = Result,
  bdd_utils:log(Config, dump, "eurl:get Result ~p: ~p", [Code, Body]),
	{ok, {{"HTTP/1.1",ReturnCode,_State}, _Head, Body}} = Result,
	{ReturnCode, Body};
get(Config, URL, OkReturnCodes) ->
  bdd_utils:log(Config, trace, "eurl:get get(Config, URL, OkReturnCodes)"),
  translateReturnCodes(get, get(Config, URL, all), OkReturnCodes, URL, get).

% prevent trying to get invalid pages from previous steps
get_page(Config, {error, Issue, URL}, _Codes) ->
  bdd_utils:log(Config, warn, "eurl:get_page aborted request due to ~p from bad URL ~p", [Issue, URL]),
  {500, Issue};
% page returns in the {CODE, BODY} format
get_page(Config, Page, Codes) -> get(Config, uri(Config, Page), Codes).
% ajax returns in the {ajax, BODY/CODE, {details}} format
get_ajax(Config, URI) ->
  case eurl:get_page(Config, URI, all) of
    {200, JSON} -> {ajax, json:parse(JSON), {get, URI}};
    {Code, _}   -> {ajax, Code, {get, URI}}
  end.
 
post_params(ParamsIn) -> post_params(ParamsIn, []).
post_params([], Params) -> Params;
post_params([{K, V} | P], ParamsOrig) -> 
  ParamsAdd = case ParamsOrig of
    [] -> "?"++K++"="++V;
    _ -> "&"++K++"="++V
  end,
  post_params(P, ParamsOrig++ParamsAdd).

% Post using Parameters to convey the values
post(Config, URL, Parameters, ReturnCode, StateRegEx) ->
  Post = URL ++ post_params(Parameters),
  {ok, {{"HTTP/1.1",ReturnCode, State}, _Head, Body}} = simple_auth:request(Config, post, {Post, "application/json", "application/json", "body"}, [{timeout, 10000}], []),  
 	{ok, StateMP} = re:compile(StateRegEx),
	case re:run(State, StateMP) of
		{match, _} -> Body;
    _ -> throw({errorWhilePosting, ReturnCode, "ERROR: post attempt at " ++ Post ++ " failed.  Return code: " ++ integer_to_list(ReturnCode) ++ " (" ++ State ++ ")~nBody: " ++ Body})
	end. 

% Post using JSON to convey the values
post(Config, Path, JSON)    -> put_post(Config, Path, JSON, post).
put(Config, Path, JSON)     -> put_post(Config, Path, JSON, put).
  
% Put using JSON to convey the values
put_post(Config, Path, JSON, Action)      -> put_post(Config, Path, JSON, Action, []).
% handle empty JSON case
put_post(Config, Path, [], Action, OkReturnCodes) -> 
  JSON = "{}",
  put_post(Config, Path, JSON, Action, OkReturnCodes);
% do the work (get all returns)
put_post(Config, Path, JSON, Action, all) ->
  URL = uri(Config, Path),
  bdd_utils:log(Config, debug, "~pting to ~p", [atom_to_list(Action), URL]),
  Result = simple_auth:request(Config, Action, {URL, [], "application/json", JSON}, [{timeout, 10000}], []),  
  {ok, {{"HTTP/1.1",ReturnCode, _State}, _Head, Body}} = Result,
  bdd_utils:log(Config, trace, "bdd_utils:put_post Result ~p: ~p", [ReturnCode, Body]),
  {ReturnCode, Body};
% deal w/ different return code options
put_post(Config, Path, JSON, Action, OkReturnCodes) ->
  translateReturnCodes(put_post, put_post(Config, Path, JSON, Action, all), OkReturnCodes, Path, Action).

form_submit(Config, Form) ->
  {fields, FormFields} = lists:keyfind(fields, 1, Form),
  {target, Target} = lists:keyfind(target, 1, Form),
  {method, Method} = lists:keyfind(method, 1, Form),
  Fields = "?" ++ string:join([ K ++ "=" ++ encode(V) || {K, V, _, _} <- FormFields],"&"),
  URL = uri(Config, path(Target, Fields)),
  bdd_utils:log(Config, debug, "eurl:form_submit ~pting to ~p", [Method, URL]),
  Result = simple_auth:request(Config, Method, {URL, [], "application/html", []}, [{timeout, 10000}], []),  
  {ok, {{"HTTP/1.1",ReturnCode, _State}, _Head, Body}} = Result,
  bdd_utils:log(Config, trace, "bdd_utils:put_post Result ~p: ~p", [ReturnCode, Body]),
  {ReturnCode, Body}.

form_fields_merge(SetField, FromFields) ->
  {Name, OldValue, ID, Type} = SetField,
  NewValue = case lists:keyfind(Name, 1, FromFields) of
    false           -> OldValue;
    {Name, Value}   -> Value;
    _               -> OldValue
  end,
  {Name, NewValue, ID, Type}.  

encode(H) when length(H) == 1 -> H;
encode([H | T]) ->
  case H of
    $   ->  "+" ++ encode(T);
    $&  ->  "%26" ++ encode(T);
    $;  ->  "%3B" ++ encode(T);
    $?  ->  "%3F" ++ encode(T);
    $:  ->  "%3A" ++ encode(T);
    $#  ->  "%23" ++ encode(T);
    $=  ->  "%3D" ++ encode(T);
    $%  ->  "%25" ++ encode(T);
    $+  ->  "%2B" ++ encode(T);
    $$  ->  "%24" ++ encode(T);
    $,  ->  "%2C" ++ encode(T);
    $.  ->  "%2E" ++ encode(T);
    $<  ->  "%3C" ++ encode(T);
    $>  ->  "%3E" ++ encode(T);
    $~  ->  "%7E" ++ encode(T);
    _   -> [H |encode(T)]
  end.

delete(Config, URL)           -> delete(Config, URL, [], all).
delete(Config, Path, [])      -> delete(Config, uri(Config, Path), [], all);
delete(Config, Path, Id)      -> delete(Config, Path, Id, []).
delete(Config, URL, [], all)  ->
  bdd_utils:log(Config, debug, "eurl:Deleting ~p", [URL]),
  Result = simple_auth:request(Config, delete, {URL}, [{timeout, 40000}], []),  
  {ok, {{"HTTP/1.1",ReturnCode, _State}, _Head, Body}} = Result,
  bdd_utils:log(Config, trace, "bdd_utils:delete Result ~p: ~p", [ReturnCode, Body]),
  {ReturnCode, Body};
delete(Config, Path, Id, all) ->
  URL = uri(Config, Path) ++ "/" ++ Id,
  delete(Config, URL, [], all);
delete(Config, Path, Id, OkReturnCodes) -> 
  translateReturnCodes(delete, delete(Config, Path, Id, all), OkReturnCodes, Path, delete).
  
% Used by get, post, put, delete to allow users to control response to return codes
translateReturnCodes(_From, {200, _},        _OkReturnCodes, _Path, delete)  -> true;
translateReturnCodes(_From, {200, Body},     _OkReturnCodes, _Path, _Action) -> Body;
translateReturnCodes(_From, {Code, _Body},   all, _Path, _Action)            -> Code; 
translateReturnCodes(_From, {_Code, _Body},  neg_one, _Path, _Action)        -> "-1";
translateReturnCodes(_From, {_Code, _Body},  error, _Path, _Action)          -> "-1";
translateReturnCodes(From,  {Code, Body},    OkReturnCodes, Path, Action)    -> 
  Listed = lists:keyfind(Code, 1, OkReturnCodes),
  case Listed of
     false -> 
        bdd_utils:log(error,"eurl:~p ~p attempt at ~p failed.  Return code: ~p in ~p", [From, Action, Path, Code, OkReturnCodes]),
        bdd_utils:log(debug,"eurl:~p Body: ~p", [From, Body]),
        throw({eURLerror, Code, Path});
     {Code, ReturnAtom} -> ReturnAtom
   end.
