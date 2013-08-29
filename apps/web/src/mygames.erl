-module(mygames).
-compile(export_all).
-include_lib("n2o/include/wf.hrl").
-include_lib("kvs/include/products.hrl").
-include_lib("kvs/include/users.hrl").
-include_lib("kvs/include/groups.hrl").
-include_lib("kvs/include/feeds.hrl").
-include_lib("kvs/include/membership.hrl").
-include_lib("kernel/include/file.hrl").
-include_lib("feed_server/include/records.hrl").

-include("records.hrl").

-define(GRP_CACHE, kvs:all(group)).

main()-> #dtl{file="prod", bindings=[{title,<<"my games">>},{body, body()}]}.

body()-> Nav = {wf:user(), mygames, []},
    InputId = wf:temp_id(),
    wf:session(game_input, InputId),
    index:header() ++ dashboard:page(Nav, [
        dashboard:section(InputId, input(#entry{}), "icon-edit"),
        #feed_view{owner=wf:user(), feed=products, title= <<"My games">>, mode=review, icon="icon-gamepad"} ]) ++index:footer().

input(#entry{}=E) ->
    MsId        = wf:temp_id(),
    TitleId     = wf:temp_id(),
    EditorId    = wf:temp_id(),
    RecipientsId= wf:temp_id(),
    PriceId     = wf:temp_id(),
    CurrencyId  = wf:temp_id(),
    User = wf:user(),
    Dir = "static/"++ case wf:user() of undefined-> "anonymous"; User -> User#user.email end,
    Medias = E#entry.media,
    Groups = [case kvs:get(group,  Where) of {ok,#group{name=T}}-> Where++"="++T; _-> [] end || #group_subscription{where=Where} <- kvs_group:participate(E#entry.entry_id)],
    P = case kvs:get(product, E#entry.entry_id) of {ok, #product{}=Pr} -> Pr; _-> #product{} end,
    case User of undefined ->[#h3{class=[blue], body= <<"">>}, index:info("Registered sellers can add the games.")]; _ ->
    #panel{id=input, body=[
    #h3{class=[blue], body= [<<"Add new game">>, #span{class=["pull-right", span3], style="color: #555555;",  body= <<"cover">>}]},
    #panel{class=["row-fluid"], body=[
    #panel{class=[span9], body=[
      #textboxlist{id=RecipientsId, placeholder= <<"Categories">>, values=string:join(Groups,",")},
      #textbox{id=TitleId, class=[span12], placeholder="Game title", value = wf:js_escape(E#entry.title)},
      #textarea{id=EditorId, class=[span12], rows="5", placeholder="Brief description", body = wf:js_escape(E#entry.description)},

      #panel{class=["input-append"], body=[
        #textbox{id=PriceId, class=[span2], value=float_to_list(P#product.price/100, [{decimals, 2}])},
        #select{id=CurrencyId, class=[selectpicker], body=[#option{label= L, body = V, selected=binary_to_list(V)==P#product.currency} || {L,V} <- ?CURRENCY]}
      ]},
      #panel{id=MsId, body=input:preview_medias(MsId, Medias, mygames)},

      #panel{class=["btn-toolbar"],body=[
        case P#product.id of undefined -> 
          #link{id=save_prod, class=?BTN_INFO, body=[#i{class=["icon-file-alt", "icon-large"]}, <<" create">>],
            postback={save, TitleId, EditorId, RecipientsId, PriceId, CurrencyId}, source=[TitleId, EditorId, PriceId, CurrencyId, RecipientsId]};
          _ -> [
            #link{class=?BTN_INFO, body=[#i{class=["icon-check", "icon-large"]}, <<" update">>],
              postback={update, P, TitleId, EditorId, RecipientsId, PriceId, CurrencyId}, source=[TitleId, EditorId, PriceId, CurrencyId, RecipientsId]},
            #link{class=?BTN_SUCCESS, body=[#i{class=["icon-retweet", "icon-large"]}, <<" cancel">>], postback={edit_product, #entry{}}}
            ]
        end
      ]}
    ]},
    #panel{class=[span3], body=[
      #upload{id=cover_upload,preview=true, root=?ROOT, dir=Dir, value=P#product.cover, delegate_query=?MODULE, post_write=attach_media, delegate_api=input, img_tool=gm, post_target=MsId, size=?THUMB_SIZE}
    ]}
  ]}
 ]} end.

controls(#entry{type=Type} =  E) -> [
  #link{body= [#i{class=["icon-edit", "icon-large"]},<<"edit">>], postback={edit_product, E}},
  #link{body=[#i{class=["icon-remove", "icon-large"]}, <<"remove">>], postback={remove_product, E}},
  #link{body=[case Type of product -> <<"view ">>; _-> <<"read more ">> end, #i{class=["icon-double-angle-right", "icon-large"]}], postback={read, Type, E#entry.id}} ].

control_event("cover_upload", {query_file, Root, Dir, File, MimeType, PostWrite, Target})->
    error_logger:info_msg("Upload cover: ~p", [Target]),
  Name = binary_to_list(File),
  Size = case file:read_file_info(filename:join([Root,Dir,Name])) of 
    {ok, FileInfo} ->
      Media = #media{
        id = element_upload:hash(filename:join([Root,Dir,Name])),
        url = filename:join([Root,Dir,Name]),
        type = {attachment, MimeType},
        thumbnail_url = filename:join([Dir,"thumbnail",Name])},
      wf:session(medias, [Media]),
      wf:update(Target, input:preview_medias(Target, [Media], mygames)),
      FileInfo#file_info.size;
    {error, _} -> 0 end,
  {exist, Size};
control_event(Id, _) ->
    error_logger:info_msg("Control id ~p", [Id]),
  SearchTerm = wf:q(term),
  Data = [ [list_to_binary(Id++"="++Name), list_to_binary(Name)] || #group{id=Id, name=Name} <- ?GRP_CACHE, string:str(string:to_lower(Name), string:to_lower(SearchTerm)) > 0],
  element_textboxlist:process_autocomplete(Id, Data, SearchTerm).

api_event(Name,Tag,Term) -> error_logger:info_msg("[account]api_event: Name ~p, Tag ~p, Term ~p",[Name,Tag,Term]).

event(init) -> wf:reg(?MAIN_CH), [];
event({delivery, [_|Route], Msg}) -> process_delivery(Route, Msg);
event({save, TitleId, BriefId, RecipientsId, PriceId, CurrencyId}) ->
    User = wf:user(),
    Title = wf:q(TitleId),
    Descr = wf:q(BriefId),
    Cats = wf:q(RecipientsId),
    Currency = wf:q(CurrencyId),
    TitlePic = case wf:session(medias) of undefined -> undefined; []-> undefined; Ms -> (lists:nth(1,Ms))#media.url--?ROOT end,
    Product = #product{
        id = kvs:uuid(),
        creator = User#user.email,
        owner = User#user.email,
        title = list_to_binary(wf:js_escape(Title)),
        brief = list_to_binary(wf:js_escape(Descr)),
        cover = TitlePic,
        price = product_ui:to_price(wf:q(PriceId)),
        currency = Currency,
        feeds = ?PRD_CHUNK,
        created = now() },

    Groups = [case kvs:get(group,S) of {error,_}->[]; {ok,G} ->G end || S<-string:tokens(Cats, ",")],

    Recipients = [{user, User#user.email, lists:keyfind(products, 1, User#user.feeds)} |
        [{group, Where, lists:keyfind(products, 1, Feeds)} || #group{id=Where, feeds=Feeds} <- Groups]],

    msg:notify([kvs_product, product, register], [Product, {Recipients, Groups}]);

event({update, #product{}=P, TitleId, EditorId, RecipientsId, PriceId, CurrencyId}) ->
  User = wf:user(),
  Title = wf:q(TitleId),
  Descr = wf:q(EditorId),
  Currency = wf:q(CurrencyId),

  TitlePic = case wf:session(medias) of undefined -> undefined; []-> undefined; Ms -> (lists:nth(1,Ms))#media.url--?ROOT end,
  Medias = case wf:session(medias) of undefined -> []; L -> L end,

  Product = P#product{
    title = list_to_binary(Title),
    brief = list_to_binary(Descr),
    cover = TitlePic,
    price = product_ui:to_price(wf:q(PriceId)),
    currency = Currency},

  Entry = #entry{
    created=Product#product.created,
    entry_id=Product#product.id,
    from=Product#product.owner,
    type= product,
    media=Medias,
    title=Product#product.title,
    description=Product#product.brief,
    shared=""},

  kvs:put(Product),

  Cats = wf:q(RecipientsId),
    error_logger:info_msg("Categories: ~p", [Cats]),
  Groups = ordsets:from_list([case kvs:get(group,S) of {error,_}->[]; {ok,G} ->G end || S<-string:tokens(Cats, ",")]),
  Participate = ordsets:from_list([ case kvs:get(group, Where) of {ok, G}->G;_->[] end  || #group_subscription{where=Where} <- kvs_group:participate(P#product.id)]),
  Intersection = ordsets:intersection(Groups, Participate),
  OldSubs = ordsets:subtract(Participate, Intersection),
  NewSubs = ordsets:subtract(Groups, Intersection),

  % stay in group and edit entry
  Rec1 = [{user, P#product.owner, lists:keyfind(products, 1, User#user.feeds)} |
    [{group, Where, lists:keyfind(products, 1, Feeds)} || #group{id=Where, feeds=Feeds} <- Intersection]],
  error_logger:info_msg("Edit recipients: ~p~n", [Rec1]),

  [msg:notify([kvs_feed, RouteType, To, entry, Eid, edit],
    Entry#entry{to = {RouteType, To}, feed_id=Fid, id={Product#product.id, Fid}}) || {RouteType, To, {_,Fid}=Eid} <- Rec1],

  % leave group and remove entry
  Rec2 = [{group,Where, lists:keyfind(products, 1, Feeds)} || #group{id=Where, feeds=Feeds} <- OldSubs],
  error_logger:info_msg("Remove recipients: ~p~n", [Rec2]),
  [msg:notify([kvs_feed, RouteType, To, entry, Eid, delete], [Entry, skip]) || {RouteType, To, Eid} <- Rec2],
  [msg:notify([kvs_group, Product#product.id, leave, G], {}) || {_,G,_} <- Rec2],
  [kvs_group:leave(Product#product.id, G) || {_,G,_} <- Rec2],

  % join group and add entry
  Rec3 = [{group, Where, lists:keyfind(products, 1, Feeds)} || #group{id=Where, feeds=Feeds} <- NewSubs],
  [kvs_group:join(Product#product.id, G) ||{_, G,_} <- Rec3],
  error_logger:info_msg("Add recipients: ~p~n", [Rec3]),
  [kvs_group:join(Product#product.id, G) || {_,G,_} <- Rec3],
  [msg:notify([kvs_group, Product#product.id, join, G], {}) || {_,G,_} <- Rec3],
  [msg:notify([kvs_feed, RoutingType, To, entry, Product#product.id, add],
  [Entry#entry{id={Product#product.id, Fid},feed_id=Fid,to = {RoutingType, To}},skip,skip,skip, To]) || {RoutingType, To, {_, Fid}} <- Rec3],

  event({edit_product, #entry{}});
event({read, product, {Id,_}})-> wf:redirect(?URL_PRODUCT(Id));
event({remove_product, E}) ->
  User = wf:user(),
  Groups = [case kvs:get(group,Where) of {error,_}->[]; {ok,G} ->G end ||
    #group_subscription{where=Where} <- kvs_group:participate(E#entry.entry_id)],

  Recipients = [{user, User#user.email, lists:keyfind(products, 1, User#user.feeds)} |
        [{group, Where, lists:keyfind(products, 1, Feeds)} || #group{id=Where, feeds=Feeds} <- Groups]],
  error_logger:info_msg("Remove pecipients: ~p", [Recipients]),

  [msg:notify([kvs_feed, RouteType, To, entry, Fid, delete], [E, User#user.email]) || {RouteType, To, Fid} <- Recipients],
  kvs_product:delete(E#entry.entry_id);
event({edit_product, #entry{}=E})->
    wf:session(medias, E#entry.media),
    wf:update(wf:session(game_input), input(E)),
    wf:wire("$('.selectpicker').each(function() {var $select = $(this); $select.selectpicker($select.data());});");
event({remove_media, M, Id}) ->
  wf:wire("$('#cover_upload').trigger('reset');"),
  input:event({remove_media, M, Id});
event(Event) -> error_logger:info_msg("[mygames]Page event: ~p", [Event]), ok.

process_delivery([_,_,entry,_,edit]=R, #entry{entry_id=Id}=E) ->
  wf:update(?ID_TOOL(Id), controls(E)),
  product:process_delivery(R,E);
process_delivery([group,_,entry,_,delete], [_,_]) -> skip;

process_delivery([product, registered], {{ok, P}, {Recipients, Groups}}) ->
    error_logger:info_msg("=>Product ~p added, notify recipients~n", [P#product.id]),
    error_logger:info_msg("Message recipients: ~p", [Recipients]),
    Medias = case wf:session(medias) of undefined -> []; M -> M end,

    [kvs_group:join(P#product.id, Id) || #group{id=Id} <- Groups],

    [msg:notify([kvs_feed, RoutingType, To, entry, P#product.id, add],
                [#entry{id={P#product.id, Fid},
                          feed_id=Fid,
                          entry_id=P#product.id,
                          created = now(),
                          to = {RoutingType, To},
                          from=P#product.owner,
                          type= product,
                          media=Medias,
                          title=P#product.title,
                          description=P#product.brief,
                          shared=""}, ok, ok, ok, ok, R]) || {RoutingType, To, {_, Fid}}=R <- Recipients];
process_delivery([product, registered], {Id, E}) -> error_logger:info_msg("Error adding product: ~p", [E]);
process_delivery(R,M) -> feed:process_delivery(R,M).
