open Syndic_common.XML
open Syndic_common.Util
module XML = Syndic_xml
module Atom = Syndic_atom

module Date = struct
  open CalendarLib
  open Printf
  open Scanf

  let month_to_int = Hashtbl.create 12
  let () =
    let add m i = Hashtbl.add month_to_int m i in
    add "Jan" 1;  add "Feb" 2;   add "Mar" 3;  add "Apr" 4;
    add "May" 5;  add "Jun" 6;   add "Jul" 7;  add "Aug" 8;
    add "Sep" 9;  add "Oct" 10;  add "Nov" 11; add "Dec" 12

  (* Format: http://www.rssboard.org/rss-specification#ltpubdategtSubelementOfLtitemgt
     Examples: Sun, 19 May 2002 15:21:36 GMT
               Sat, 25 Sep 2010 08:01:00 -0700
               20 Mar 2013 03:47:14 +0000 *)
  let of_string s =
    let make_date day month year h m maybe_s z =
      let month = if String.length month <= 3 then month
                  else String.sub month 0 3 in
      let month = Hashtbl.find month_to_int month in
      let date = Calendar.Date.make year month day in
      let s =
        if maybe_s <> "" && maybe_s.[0] = ':' then
          float_of_string(String.sub maybe_s 1 (String.length maybe_s - 1))
        else 0. in
      let t = Calendar.Time.(make h m (Second.from_float s)) in
      if z = "" || z = "GMT" || z = "UT" then
        Calendar.(create date t)
      else
        (* FIXME: this should be made more robust. *)
        let zh = sscanf (String.sub z 0 3) "%i" (fun i -> i)
        and zm = sscanf (String.sub z 3 2) "%i" (fun i -> i) in
        let tz = Calendar.Time.(Period.make zh zm (Second.from_int 0)) in
        Calendar.(create date (Time.add t tz))
    in
    try
      if 'A' <= s.[0] && s.[0] <= 'Z' then (
        try sscanf s "%_s %i %s %i %i:%i%s %s" make_date
        with _ ->
          sscanf s "%_s %ist %s %i %i:%i%s %s" make_date
      )
      else (
        try sscanf s "%i %s %i %i:%i%s %s" make_date
        with _ ->
          sscanf s "%i %s %i" (fun d m y -> make_date d m y 0 0 "" "UT")
      )
    with _ ->
      invalid_arg(sprintf "Syndic.Rss2.Date.of_string: cannot parse %S" s)
end

module Error = Syndic_error

type image =
  {
    url: Uri.t;
    title: string;
    link: Uri.t;
    width: int; (* default 88 *)
    height: int; (* default 31 *)
    description: string option;
  }

type image' = [
  | `URL of Uri.t
  | `Title of string
  | `Link of Uri.t
  | `Width of int
  | `Height of int
  | `Description of string
]

let make_image ~pos (l : [< image' ] list) =
  let url = match find (function `URL _ -> true | _ -> false) l with
    | Some (`URL u) -> u
    | _ ->
      raise (Error.Error (pos,
                            "<image> elements MUST contains exactly one \
                             <url> element"))
  in
  let title = match find (function `Title _ -> true | _ -> false) l with
    | Some (`Title t) -> t
    | _ ->
      raise (Error.Error (pos,
                            "<image> elements MUST contains exactly one \
                             <title> element"))
  in
  let link = match find (function `Link _ -> true | _ -> false) l with
    | Some (`Link l) -> l
    | _ ->
      raise (Error.Error (pos,
                            "<image> elements MUST contains exactly one \
                             <link> element"))
  in
  let width = match find (function `Width _ -> true | _ -> false) l with
    | Some (`Width w) -> w
    | _ -> 88 (* cf. RFC *)
  in
  let height = match find (function `Height _ -> true | _ -> false) l with
    | Some (`Height h) -> h
    | _ -> 31 (* cf. RFC *)
  in
  let description =
    match find (function `Description _ -> true | _ -> false) l with
    | Some (`Description s) -> Some s
    | _ -> None
  in
  ({ url; title; link; width; height; description } : image)

let image_url_of_xml (pos, tag, datas) =
  try Uri.of_string (get_leaf datas)
  with Not_found -> raise (Error.Error (pos,
                            "The content of <uri> MUST be \
                             a non-empty string"))

let image_title_of_xml (pos, tag, datas) =
  try get_leaf datas
  with Not_found -> ""

let image_link_of_xml (pos, tag, datas) =
  try Uri.of_string (get_leaf datas)
  with Not_found -> raise (Error.Error (pos,
                            "The content of <link> MUST be \
                             a non-empty string"))

let image_size_of_xml ~max (pos, tag, datas) =
  try let size = int_of_string (get_leaf datas) in
    if size > max
    then raise (Error.Error
                  (pos, ("size of "  ^ (get_tag_name tag)
                         ^ " exceeded (max is " ^ (string_of_int max) ^ ")")))
    else size
  with Not_found -> raise (Error.Error (pos,
                            ("The content of <"^(get_tag_name tag)^"> MUST be \
                              a non-empty string")))
     | Failure "int_of_string" -> raise (Error.Error (pos,
                            ("The content of <"^(get_tag_name tag)^"> MUST be \
                              an integer")))

let image_width_of_xml = image_size_of_xml ~max:144
let image_height_of_xml = image_size_of_xml ~max:400

let image_description_of_xml (pos, tag, datas) =
  try get_leaf datas
  with Not_found -> raise (Error.Error (pos,
                            "The content of <description> MUST be \
                             a non-empty string"))

let image_of_xml ((pos, _, _) as xml) =
  let data_producer = [
    ("url", (fun ctx a -> `URL (image_url_of_xml a)));
    ("title", (fun ctx a -> `Title (image_title_of_xml a)));
    ("link", (fun ctx a -> `Link (image_link_of_xml a)));
    ("width", (fun ctx a -> `Width (image_width_of_xml a)));
    ("height", (fun ctx a -> `Height (image_height_of_xml a)));
    ("description", (fun ctx a -> `Description (image_description_of_xml a)));
  ] in
  generate_catcher ~data_producer (make_image ~pos) xml

let image_of_xml' =
  let data_producer = [
    ("url", (fun ctx -> dummy_of_xml ~ctor:(fun a -> `URL a)));
    ("title", (fun ctx -> dummy_of_xml ~ctor:(fun a -> `Title a)));
    ("link", (fun ctx -> dummy_of_xml ~ctor:(fun a -> `Link a)));
    ("width", (fun ctx -> dummy_of_xml ~ctor:(fun a -> `Width a)));
    ("height", (fun ctx -> dummy_of_xml ~ctor:(fun a -> `Height a)));
    ("description", (fun ctx -> dummy_of_xml ~ctor:(fun a -> `Description a)));
  ] in
  generate_catcher ~data_producer (fun x -> x)

type cloud = {
  domain: Uri.t;
  port: int;
  path: string;
  registerProcedure: string;
  protocol: string;
}

type cloud' = [
  | `Domain of string
  | `Port of string
  | `Path of string
  | `RegisterProcedure of string
  | `Protocol of string
]

let make_cloud ~pos (l : [< cloud' ] list) =
  let domain = match find (function `Domain _ -> true | _ -> false) l with
    | Some (`Domain u) -> (Uri.of_string u)
    | _ ->
      raise (Error.Error (pos,
                            "Cloud elements MUST have a 'domain' \
                             attribute"))
  in
  let port = match find (function `Port _ -> true | _ -> false) l with
    | Some (`Port p) -> (int_of_string p)
    | _ ->
      raise (Error.Error (pos,
                            "Cloud elements MUST have a 'port' \
                             attribute"))
  in
  let path = match find (function `Path _ -> true | _ -> false) l with
    | Some (`Path p) -> p
    | _ ->
      raise (Error.Error (pos,
                            "Cloud elements MUST have a 'path' \
                             attribute"))
  in
  let registerProcedure =
    match find (function `RegisterProcedure _ -> true | _ -> false) l with
    | Some (`RegisterProcedure r) -> r
    | _ ->
      raise (Error.Error (pos,
                            "Cloud elements MUST have a 'registerProcedure' \
                             attribute"))
  in
  let protocol = match find (function `Protocol _ -> true | _ -> false) l with
    | Some (`Protocol p) -> p
    | _ ->
      raise (Error.Error (pos,
                            "Cloud elements MUST have a 'protocol' \
                             attribute"))
  in
  ({ domain; port; path; registerProcedure; protocol; } : cloud)

let cloud_of_xml, cloud_of_xml' =
  let attr_producer = [
    ("domain", (fun ctx pos a -> `Domain a));
    ("port", (fun ctx pos a -> `Port a));
    ("path", (fun ctx pos a -> `Path a)); (* XXX: it's RFC compliant ? *)
    ("registerProcedure", (fun ctx pos a -> `RegisterProcedure a));
    ("protocol", (fun ctx pos a -> `Protocol a));
  ] in
  (fun ((pos, _, _) as xml) ->
     generate_catcher ~attr_producer (make_cloud ~pos) xml),
  generate_catcher ~attr_producer (fun x -> x)

type textinput =
  {
    title: string;
    description: string;
    name: string;
    link: Uri.t;
  }

type textinput' = [
  | `Title of string
  | `Description of string
  | `Name of string
  | `Link of Uri.t
]

let make_textinput ~pos (l : [< textinput'] list) =
  let title = match find (function `Title _ -> true | _ -> false) l with
    | Some (`Title t) -> t
    | _ ->
      raise (Error.Error (pos,
                            "<textinput> elements MUST contains exactly one \
                             <title> element"))
  in
  let description =
    match find (function `Description _ -> true | _ -> false) l with
    | Some (`Description s) -> s
    | _ ->
      raise (Error.Error (pos,
                            "<textinput> elements MUST contains exactly one \
                             <description> element"))
  in
  let name = match find (function `Name _ -> true | _ -> false) l with
    | Some (`Name s) -> s
    | _ ->
      raise (Error.Error (pos,
                            "<textinput> elements MUST contains exactly one \
                             <name> element"))
  in
  let link = match find (function `Link _ -> true | _ -> false) l with
    | Some (`Link u) -> u
    | _ ->
      raise (Error.Error (pos,
                            "<textinput> elements MUST contains exactly one \
                             <link> element"))
  in
  ({ title; description; name; link; } : textinput)

let textinput_title_of_xml (pos, tag, datas) =
  try get_leaf datas
  with Not_found -> raise (Error.Error (pos,
                            "The content of <title> MUST be \
                             a non-empty string"))

let textinput_description_of_xml (pos, tag, datas) =
  try get_leaf datas
  with Not_found -> raise (Error.Error (pos,
                            "The content of <description> MUST be \
                             a non-empty string"))

let textinput_name_of_xml (pos, tag, datas) =
  try get_leaf datas
  with Not_found -> raise (Error.Error (pos,
                            "The content of <name> MUST be \
                             a non-empty string"))

let textinput_link_of_xml (pos, tag, datas) =
  try Uri.of_string (get_leaf datas)
  with Not_found -> raise (Error.Error (pos,
                            "The content of <link> MUST be \
                             a non-empty string"))

let textinput_of_xml ((pos, _, _) as xml)=
  let data_producer = [
    ("title", (fun ctx a -> `Title (textinput_title_of_xml a)));
    ("description",
     (fun ctx a -> `Description (textinput_description_of_xml a)));
    ("name", (fun ctx a -> `Name (textinput_name_of_xml a)));
    ("link", (fun ctx a -> `Link (textinput_link_of_xml a)));
  ] in
  generate_catcher ~data_producer (make_textinput ~pos) xml

let textinput_of_xml' =
  let data_producer = [
    ("title", (fun ctx -> dummy_of_xml ~ctor:(fun a -> `Title a)));
    ("description",
     (fun ctx -> dummy_of_xml ~ctor:(fun a -> `Description a)));
    ("name", (fun ctx -> dummy_of_xml ~ctor:(fun a -> `Name a)));
    ("link", (fun ctx -> dummy_of_xml ~ctor:(fun a -> `Link a)));
  ] in
  generate_catcher ~data_producer (fun x -> x)

type category =
  {
    data: string;
    domain: Uri.t option;
  }

type category' = [
  | `Data of string
  | `Domain of string
]

let make_category (l : [< category' ] list) =
  let data = match find (function `Data _ -> true | _ -> false) l with
    | Some (`Data s)-> s
    | _ -> ""
  in let domain = match find (function `Domain _ -> true | _ -> false) l with
    | Some (`Domain d) -> Some (Uri.of_string d)
    | _ -> None
  in
  ({ data; domain; } : category )

let category_of_xml, category_of_xml' =
  let attr_producer = [ ("domain", (fun ctx pos a -> `Domain a)); ] in
  let leaf_producer ctx pos data = `Data data in
  generate_catcher ~attr_producer ~leaf_producer make_category,
  generate_catcher ~attr_producer ~leaf_producer (fun x -> x)

type enclosure =
  {
    url: Uri.t;
    length: int;
    mime: string;
  }

type enclosure' = [
  | `URL of string
  | `Length of string
  | `Mime of string
]

let make_enclosure ~pos (l : [< enclosure' ] list) =
  let url = match find (function `URL _ -> true | _ -> false) l with
    | Some (`URL u) -> Uri.of_string u
    | _ ->
      raise (Error.Error (pos,
                            "Enclosure elements MUST have a 'url' \
                             attribute"))
  in
  let length = match find (function `Length _ -> true | _ -> false) l with
    | Some (`Length l) -> int_of_string l
    | _ ->
      raise (Error.Error (pos,
                            "Enclosure elements MUST have a 'length' \
                             attribute"))
  in
  let mime = match find (function `Mime _ -> true | _ -> false) l with
    | Some (`Mime m) -> m
    | _ ->
      raise (Error.Error (pos,
                            "Enclosure elements MUST have a 'type' \
                             attribute"))
  in
  ({ url; length; mime; } : enclosure)

let enclosure_of_xml, enclosure_of_xml' =
  let attr_producer = [
    ("url", (fun ctx pos a -> `URL a));
    ("length", (fun ctx pos a -> `Length a));
    ("type", (fun ctx pos a -> `Mime a));
  ] in
  (fun ((pos, _, _) as xml) ->
     generate_catcher ~attr_producer (make_enclosure ~pos) xml),
  generate_catcher ~attr_producer (fun x -> x)

type guid =
  {
    data: Uri.t; (* must be uniq *)
    permalink: bool; (* default true *)
  }

type guid' = [
  | `Data of string
  | `Permalink of string
]

(* Some RSS2 server output <guid isPermaLink="false"></guid> ! *)
let make_guid (l : [< guid' ] list) =
  let data = match find (function `Data _ -> true | _ -> false) l with
    | Some (`Data u) -> u
    | _ -> ""
  in
  let permalink = match find (function `Permalink _ -> true | _ -> false) l with
    | Some (`Permalink b) -> bool_of_string b
    | _ -> true (* cf. RFC *)
  in
  if data = "" then None
  else Some({ data = Uri.of_string data;  permalink } : guid)

let guid_of_xml, guid_of_xml' =
  let attr_producer = [ ("isPermalink", (fun ctx pos a -> `Permalink a)); ] in
  let leaf_producer ctx pos data = `Data data in
  generate_catcher ~attr_producer ~leaf_producer make_guid,
  generate_catcher ~attr_producer ~leaf_producer (fun x -> x)

type source =
  {
    data: string;
    url: Uri.t;
  }

type source' = [
  | `Data of string
  | `URL of string
]

let make_source ~pos (l : [< source' ] list) =
  let data = match find (function `Data _ -> true | _ -> false) l with
    | Some (`Data s) -> s
    | _  -> raise (Error.Error (pos,
                            "The content of <source> MUST be \
                             a non-empty string"))
  in
  let url = match find (function `URL _ -> true | _ -> false) l with
    | Some (`URL u) -> Uri.of_string u
    | _ ->
      raise (Error.Error (pos,
                            "Source elements MUST have a 'url' \
                             attribute"))
  in
  ({ data; url; } : source)

let source_of_xml, source_of_xml' =
  let attr_producer = [ ("url", (fun ctx pos a -> `URL a)); ] in
  let leaf_producer ctx pos data = `Data data in
  (fun ((pos, _, _) as xml) ->
     generate_catcher ~attr_producer ~leaf_producer (make_source ~pos) xml),
  generate_catcher ~attr_producer ~leaf_producer (fun x -> x)

type story =
  | All of string * string
  | Title of string
  | Description of string

type item =
  {
    story: story;
    link: Uri.t option;
    author:  string option; (* e-mail *)
    category: category option;
    comments: Uri.t option;
    enclosure: enclosure option;
    guid: guid option;
    pubDate: CalendarLib.Calendar.t option; (* date *)
    source: source option;
  }

type item' = [
  | `Title of string
  | `Description of string
  | `Link of Uri.t
  | `Author of string (* e-mail *)
  | `Category of category
  | `Comments of Uri.t
  | `Enclosure of enclosure
  | `Guid of guid
  | `PubDate of CalendarLib.Calendar.t
  | `Source of source
]

let make_item ~pos (l : _ list) =
  let story = match
      find (function `Title _ -> true | _ -> false) l,
      find (function `Description _ -> true | _ -> false) l
    with
    | Some (`Title t), Some (`Description d) -> All (t, d)
    | Some (`Title t), _ -> Title t
    | _, Some (`Description d) -> Description d
    | _, _ -> raise (Error.Error (pos,
                                  "Item expected <title> or <description> tag"))
  in
  let link = match find (function `Link _ -> true | _ -> false) l with
    | Some (`Link l) -> l
    | _ -> None
  in
  let author = match find (function `Author _ -> true | _ -> false) l with
    | Some (`Author a) -> Some a
    | _ -> None
  in
  let category = match find (function `Category _ -> true | _ -> false) l with
    | Some (`Category c) -> Some c
    | _ -> None
  in
  let comments = match find (function `Comments _ -> true | _ -> false) l with
    | Some (`Comments c) -> Some c
    | _ -> None
  in
  let enclosure = match find (function `Enclosure _ -> true | _ -> false) l with
    | Some (`Enclosure e) -> Some e
    | _ -> None
  in
  let guid = match find (function `Guid _ -> true | _ -> false) l with
    | Some (`Guid g) -> g
    | _ -> None
  in
  let pubDate = match find (function `PubDate _ -> true | _ -> false) l with
    | Some (`PubDate p) -> Some p
    | _ -> None
  in
  let source = match find (function `Source _ -> true | _ -> false) l with
    | Some (`Source s) -> Some s
    | _ -> None
  in
  ({ story;
     link;
     author;
     category;
     comments;
     enclosure;
     guid;
     pubDate;
     source; } : item)

let item_title_of_xml (pos, tag, datas) =
  try get_leaf datas
  with Not_found -> raise (Error.Error (pos,
                            "The content of <title> MUST be \
                             a non-empty string"))

let item_description_of_xml (pos, tag, datas) =
  try get_leaf datas
  with Not_found -> ""

let item_link_of_xml (pos, tag, datas) =
  try Some(Uri.of_string (get_leaf datas))
  with Not_found -> None

let item_author_of_xml (pos, tag, datas) =
  try get_leaf datas
  with Not_found -> raise (Error.Error (pos,
                            "The content of <author> MUST be \
                             a non-empty string"))

let item_comments_of_xml (pos, tag, datas) =
  try Uri.of_string (get_leaf datas)
  with Not_found -> raise (Error.Error (pos,
                            "The content of <comments> MUST be \
                             a non-empty string"))

let item_pubdate_of_xml (pos, tag, datas) =
  try Date.of_string (get_leaf datas)
  with Not_found -> raise (Error.Error (pos,
                            "The content of <pubDate> MUST be \
                             a non-empty string"))

let item_of_xml ((pos, _, _) as xml) =
  let data_producer = [
    ("title", (fun ctx a -> `Title (item_title_of_xml a)));
    ("description", (fun ctx a -> `Description (item_description_of_xml a)));
    ("link", (fun ctx a -> `Link (item_link_of_xml a)));
    ("author", (fun ctx a -> `Author (item_author_of_xml a)));
    ("category", (fun ctx a -> `Category (category_of_xml a)));
    ("comments", (fun ctx a -> `Comments (item_comments_of_xml a)));
    ("enclosure", (fun ctx a -> `Enclosure (enclosure_of_xml a)));
    ("guid", (fun ctx a -> `Guid (guid_of_xml a)));
    ("pubDate", (fun ctx a -> `PubDate (item_pubdate_of_xml a)));
    ("source", (fun ctx a -> `Source (source_of_xml a)));
  ] in
  generate_catcher ~data_producer (make_item ~pos) xml

let item_of_xml' =
  let data_producer = [
    ("title", (fun ctx -> dummy_of_xml ~ctor:(fun a -> `Title a)));
    ("description",
     (fun ctx -> dummy_of_xml ~ctor:(fun a -> `Description a)));
    ("link", (fun ctx -> dummy_of_xml ~ctor:(fun a -> `Link a)));
    ("author", (fun ctx -> dummy_of_xml ~ctor:(fun a -> `Author a)));
    ("category", (fun ctx a -> `Category (category_of_xml' a)));
    ("comments", (fun ctx -> dummy_of_xml ~ctor:(fun a -> `Comments a)));
    ("enclosure", (fun ctx a -> `Enclosure (enclosure_of_xml' a)));
    ("guid", (fun ctx a -> `Guid (guid_of_xml' a)));
    ("pubdate", (fun ctx -> dummy_of_xml ~ctor:(fun a -> `PubDate a)));
    ("source", (fun ctx a -> `Source (source_of_xml' a)));
  ] in
  generate_catcher ~data_producer (fun x -> x)

type channel =
  {
    title: string;
    link: Uri.t;
    description: string;
    language: string option;
    copyright: string option;
    managingEditor: string option;
    webMaster: string option;
    pubDate: CalendarLib.Calendar.t option;
    lastBuildDate: CalendarLib.Calendar.t option;
    category: string option;
    generator: string option;
    docs: Uri.t option;
    cloud: cloud option;
    ttl: int option;
    image: image option;
    rating: int option;
    textInput: textinput option;
    skipHours: int option;
    skipDays: int option;
    items: item list;
  }

type channel' = [
  | `Title of string
  | `Link of Uri.t
  | `Description of string
  | `Language of string
  | `Copyright of string
  | `ManagingEditor of string
  | `WebMaster of string
  | `PubDate of CalendarLib.Calendar.t
  | `LastBuildDate of CalendarLib.Calendar.t
  | `Category of string
  | `Generator of string
  | `Docs of Uri.t
  | `Cloud of cloud
  | `TTL of int
  | `Image of image
  | `Rating of int
  | `TextInput of textinput
  | `SkipHours of int
  | `SkipDays of int
  | `Item of item
]

let make_channel ~pos (l : [< channel' ] list) =
  let title = match find (function `Title _ -> true | _ -> false) l with
    | Some (`Title t) -> t
    | _ ->
      raise (Error.Error (pos,
                            "<channel> elements MUST contains exactly one \
                             <title> element"))
  in
  let link = match find (function `Link _ -> true | _ -> false) l with
    | Some (`Link l) -> l
    | _ ->
      raise (Error.Error (pos,
                            "<channel> elements MUST contains exactly one \
                             <link> element"))
  in
  let description =
    match find (function `Description _ -> true | _ -> false) l with
    | Some (`Description l) -> l
    | _ ->
      raise (Error.Error (pos,
                            "<channel> elements MUST contains exactly one \
                             <description> element"))
  in
  let language = match find (function `Language _ -> true | _ -> false) l with
    | Some (`Language a) -> Some a
    | _ -> None
  in
  let copyright = match find (function `Copyright _ -> true | _ -> false) l with
    | Some (`Copyright a) -> Some a
    | _ -> None
  in
  let managingEditor =
    match find (function `ManagingEditor _ -> true | _ -> false) l with
    | Some (`ManagingEditor a) -> Some a
    | _ -> None
  in
  let webMaster = match find (function `WebMaster _ -> true | _ -> false) l with
    | Some (`WebMaster a) -> Some a
    | _ -> None
  in
  let pubDate = match find (function `PubDate _ -> true | _ -> false) l with
    | Some (`PubDate a) -> Some a
    | _ -> None
  in
  let lastBuildDate =
    match find (function `LastBuildDate _ -> true | _ -> false) l with
    | Some (`LastBuildDate a) -> Some a
    | _ -> None
  in
  let category = match find (function `Category _ -> true | _ -> false) l with
    | Some (`Category a) -> Some a
    | _ -> None
  in
  let generator = match find (function `Generator _ -> true | _ -> false) l with
    | Some (`Generator a) -> Some a
    | _ -> None
  in
  let docs = match find (function `Docs _ -> true | _ -> false) l with
    | Some (`Docs a) -> Some a
    | _ -> None
  in
  let cloud = match find (function `Cloud _ -> true | _ -> false) l with
    | Some (`Cloud a) -> Some a
    | _ -> None
  in
  let ttl = match find (function `TTL _ -> true | _ -> false) l with
    | Some (`TTL a) -> Some a
    | _ -> None
  in
  let image = match find (function `Image _ -> true | _ -> false) l with
    | Some (`Image a) -> Some a
    | _ -> None
  in
  let rating = match find (function `Rating _ -> true | _ -> false) l with
    | Some (`Rating a) -> Some a
    | _ -> None
  in
  let textInput = match find (function `TextInput _ -> true | _ -> false) l with
    | Some (`TextInput a) -> Some a
    | _ -> None
  in
  let skipHours = match find (function `SkipHours _ -> true | _ -> false) l with
    | Some (`SkipHours a) -> Some a
    | _ -> None
  in
  let skipDays = match find (function `SkipDays _ -> true | _ -> false) l with
    | Some (`SkipDays a) -> Some a
    | _ -> None
  in
  let items = List.fold_left
      (fun acc -> function `Item x -> x :: acc | _ -> acc) [] l in
  ({ title;
     link;
     description;
     language;
     copyright;
     managingEditor;
     webMaster;
     pubDate;
     lastBuildDate;
     category;
     generator;
     docs;
     cloud;
     ttl;
     image;
     rating;
     textInput;
     skipHours;
     skipDays;
     items; } : channel)

let channel_title_of_xml (pos, tag, datas) =
  try get_leaf datas
  with Not_found -> raise (Error.Error (pos,
                            "The content of <title> MUST be \
                             a non-empty string"))

let channel_description_of_xml (pos, tag, datas) =
  try get_leaf datas
  with Not_found -> ""

let channel_link_of_xml (pos, tag, datas) =
  try Uri.of_string (get_leaf datas)
  with Not_found -> raise (Error.Error (pos,
                            "The content of <link> MUST be \
                             a non-empty string"))

let channel_language_of_xml (pos, tag, datas) =
  try get_leaf datas
  with Not_found -> raise (Error.Error (pos,
                            "The content of <language> MUST be \
                             a non-empty string"))

let channel_copyright_of_xml (pos, tag, datas) =
  try get_leaf datas
  with Not_found -> raise (Error.Error (pos,
                            "The content of <copyright> MUST be \
                             a non-empty string"))

let channel_managingeditor_of_xml (pos, tag, datas) =
  try get_leaf datas
  with Not_found -> raise (Error.Error (pos,
                            "The content of <managingEditor> MUST be \
                             a non-empty string"))

let channel_webmaster_of_xml (pos, tag, datas) =
  try get_leaf datas
  with Not_found -> raise (Error.Error (pos,
                            "The content of <webMaster> MUST be \
                             a non-empty string"))

let channel_pubdate_of_xml (pos, tag, datas) =
  try Date.of_string (get_leaf datas)
  with Not_found -> raise (Error.Error (pos,
                            "The content of <pubDate> MUST be \
                             a non-empty string"))

let channel_lastbuilddate_of_xml (pos, tag, datas) =
  try Date.of_string (get_leaf datas)
  with Not_found -> raise (Error.Error (pos,
                            "The content of <lastBuildDate> MUST be \
                             a non-empty string"))

let channel_category_of_xml (pos, tag, datas) =
  try get_leaf datas
  with Not_found -> raise (Error.Error (pos,
                            "The content of <category> MUST be \
                             a non-empty string"))

let channel_generator_of_xml (pos, tag, datas) =
  try get_leaf datas
  with Not_found -> raise (Error.Error (pos,
                            "The content of <generator> MUST be \
                             a non-empty string"))

let channel_docs_of_xml (pos, tag, datas) =
  try Uri.of_string (get_leaf datas)
  with Not_found -> raise (Error.Error (pos,
                            "The content of <docs> MUST be \
                             a non-empty string"))

let channel_ttl_of_xml (pos, tag, datas) =
  try int_of_string (get_leaf datas)
  with Not_found -> raise (Error.Error (pos,
                            "The content of <ttl> MUST be \
                             a non-empty string"))

let channel_rating_of_xml (pos, tag, datas) =
  try int_of_string (get_leaf datas)
  with Not_found -> raise (Error.Error (pos,
                            "The content of <rating> MUST be \
                             a non-empty string"))

let channel_skipHours_of_xml (pos, tag, datas) =
  try int_of_string (get_leaf datas)
  with Not_found -> raise (Error.Error (pos,
                            "The content of <skipHours> MUST be \
                             a non-empty string"))

let channel_skipDays_of_xml (pos, tag, datas) =
  try int_of_string (get_leaf datas)
  with Not_found -> raise (Error.Error (pos,
                            "The content of <skipDays> MUST be \
                             a non-empty string"))

let channel_of_xml ((pos, _, _) as xml) =
  let data_producer = [
    ("title", (fun ctx a -> `Title (channel_title_of_xml a)));
    ("link", (fun ctx a -> `Link (channel_link_of_xml a)));
    ("description", (fun ctx a -> `Description (channel_description_of_xml a)));
    ("Language", (fun ctx a -> `Language (channel_language_of_xml a)));
    ("copyright", (fun ctx a -> `Copyright (channel_copyright_of_xml a)));
    ("managingeditor",
     (fun ctx a -> `ManagingEditor (channel_managingeditor_of_xml a)));
    ("webmaster", (fun ctx a -> `WebMaster (channel_webmaster_of_xml a)));
    ("pubdate", (fun ctx a -> `PubDate (channel_pubdate_of_xml a)));
    ("lastbuilddate",
     (fun ctx a -> `LastBuildDate (channel_lastbuilddate_of_xml a)));
    ("category", (fun ctx a -> `Category (channel_category_of_xml a)));
    ("generator", (fun ctx a -> `Generator (channel_generator_of_xml a)));
    ("docs", (fun ctx a -> `Docs (channel_docs_of_xml a)));
    ("cloud", (fun ctx a -> `Cloud (cloud_of_xml a)));
    ("ttl", (fun ctx a -> `TTL (channel_ttl_of_xml a)));
    ("image", (fun ctx a -> `Image (image_of_xml a)));
    ("rating", (fun ctx a -> `Rating (channel_rating_of_xml a)));
    ("textinput", (fun ctx a -> `TextInput (textinput_of_xml a)));
    ("skiphours", (fun ctx a -> `SkipHours (channel_skipHours_of_xml a)));
    ("skipdays", (fun ctx a -> `SkipDays (channel_skipDays_of_xml a)));
    ("item", (fun ctx a -> `Item (item_of_xml a)));
  ] in
  generate_catcher ~data_producer (make_channel ~pos) xml

let channel_of_xml' =
  let data_producer = [
    ("title", (fun ctx -> dummy_of_xml ~ctor:(fun a -> `Title a)));
    ("link", (fun ctx -> dummy_of_xml ~ctor:(fun a -> `Link a)));
    ("description", (fun ctx -> dummy_of_xml ~ctor:(fun a -> `Description a)));
    ("Language", (fun ctx -> dummy_of_xml ~ctor:(fun a -> `Language a)));
    ("copyright", (fun ctx -> dummy_of_xml ~ctor:(fun a -> `Copyright a)));
    ("managingeditor",
     (fun ctx -> dummy_of_xml ~ctor:(fun a -> `ManagingEditor a)));
    ("webmaster", (fun ctx -> dummy_of_xml ~ctor:(fun a -> `WebMaster a)));
    ("pubdate", (fun ctx -> dummy_of_xml ~ctor:(fun a -> `PubDate a)));
    ("lastbuilddate",
     (fun ctx -> dummy_of_xml ~ctor:(fun a -> `LastBuildDate a)));
    ("category", (fun ctx -> dummy_of_xml ~ctor:(fun a -> `Category a)));
    ("generator", (fun ctx -> dummy_of_xml ~ctor:(fun a -> `Generator a)));
    ("docs", (fun ctx -> dummy_of_xml ~ctor:(fun a -> `Docs a)));
    ("cloud", (fun ctx a -> `Cloud (cloud_of_xml' a)));
    ("ttl", (fun ctx -> dummy_of_xml ~ctor:(fun a -> `TTL a)));
    ("image", (fun ctx a -> `Image (image_of_xml' a)));
    ("rating", (fun ctx -> dummy_of_xml ~ctor:(fun a -> `Rating a)));
    ("textinput", (fun ctx a -> `TextInput (textinput_of_xml' a)));
    ("skiphours", (fun ctx -> dummy_of_xml ~ctor:(fun a -> `SkipHours a)));
    ("skipdays", (fun ctx -> dummy_of_xml ~ctor:(fun a -> `SkipDays a)));
    ("item", (fun ctx a -> `Item (item_of_xml' a)));
  ] in
  generate_catcher ~data_producer (fun x -> x)

let find_channel l =
  find (function XML.Node(pos, tag, data) -> tag_is tag "channel"
                | XML.Data _ -> false) l

let parse input =
  match XML.of_xmlm input |> snd with
  | XML.Node (pos, tag, data) ->
     if tag_is tag "channel" then
       channel_of_xml (pos, tag, data)
     else (
       match find_channel data with
       | Some(XML.Node(p, t, d)) -> channel_of_xml (p, t, d)
       | Some(XML.Data _)
       | _ -> raise (Error.Error ((0, 0),
                              "document MUST contains exactly one \
                               <channel> element")))
  | _ -> raise (Error.Error ((0, 0),
                         "document MUST contains exactly one \
                          <channel> element"))

let unsafe input =
  match XML.of_xmlm input |> snd with
  | XML.Node (pos, tag, data) ->
     if tag_is tag "channel" then `Channel (channel_of_xml' (pos, tag, data))
     else (match find_channel data with
           | Some(XML.Node(p, t, d)) -> `Channel (channel_of_xml' (p, t, d))
           | Some(XML.Data _) | None -> `Channel [])
  | _ -> `Channel []


(* Conversion to Atom *)

let map_option o f = match o with
  | None -> None
  | Some v -> Some(f v)

let cmp_date_opt d1 d2 = match d1, d2 with
  | Some d1, Some d2 -> CalendarLib.Calendar.compare d1 d2
  | Some _, None -> 1
  | None, Some _ -> -1
  | None, None -> 0

let epoch = CalendarLib.Calendar.from_unixfloat 0. (* 1970-1-1 *)

let entry_of_item (it: item) : Atom.entry =
  let author = match it.author with
    | Some a -> { Atom.name = a;  uri = None;  email = Some a }
    | None -> { Atom.name = "";  uri = None;  email = None } in
  let categories =
    match it.category with
    | Some c -> [ { Atom.term = c.data;
                   scheme = map_option c.domain (fun d -> d);
                   label = None } ]
    | None -> [] in
  let (title: Atom.title), content = match it.story with
    | All(t, d) -> Atom.Text t, Some(Atom.Html d)
    | Title t -> Atom.Text t, None
    | Description d -> Atom.Text "", Some(Atom.Html d) in
  let id = match it.guid with
    | Some g -> Uri.to_string g.data
    | None -> match it.link with
             | Some l -> Uri.to_string l
             | None ->
                let s = match it.story with
                  | All(t, d) -> t ^ d
                  | Title t -> t
                  | Description d -> d in
                Digest.to_hex (Digest.string s) in
  let links = match it.link with
    | Some l -> [ { Atom.href = l;  rel = Atom.Alternate;
                   type_media = None;  hreflang = None;  title = None;
                   length = None } ]
    | None -> [] in
  let links = match it.comments with
    | Some l -> { Atom.href = l;  rel = Atom.Related;
                 type_media = None;  hreflang = None;  title = None;
                 length = None }
               :: links
    | None -> links in
  let links = match it.enclosure with
    | Some e -> { Atom.href = e.url;  rel = Atom.Enclosure;
                 type_media = Some e.mime;
                 hreflang = None;  title = None;  length = Some e.length }
               :: links
    | None -> links in
  let sources = match it.source with
    | Some s ->
       [ { Atom.authors = (author, []); (* Best guess *)
           categories = [];
           contributors = [];
           generator = None;
           icon = None;
           id;
           links = [ { Atom.href = s.url;  rel = Atom.Related;
                       type_media = None;  hreflang = None;  title = None;
                       length = None} ];
           logo = None;
           rights = None;
           subtitle = None;
           title = Atom.Text s.data;
           updated = None } ]
    | None -> [] in
  { Atom.
    authors = (author, []);
    categories;
    content;
    contributors = [];
    id;
    links;
    published = None;
    rights = None;
    sources;
    summary = None;
    title;
    updated = (match it.pubDate with
               | Some d -> d
               | None -> epoch);
  }

let to_atom (ch: channel) : Atom.feed =
  let contributors = match ch.webMaster with
    | Some p -> [ { Atom.name = "Webmaster";  uri = None;  email = Some p } ]
    | None -> [] in
  let contributors = match ch.managingEditor with
    | Some p -> { Atom.name = "Managing Editor";  uri = None;  email = Some p }
               :: contributors
    | None -> contributors in
  let updated =
    let d = List.map (fun (it: item) -> it.pubDate) ch.items in
    let d = List.sort cmp_date_opt (ch.lastBuildDate :: d) in
    match d with
    | Some d :: _ -> d
    | None :: _ -> epoch
    | [] -> assert false in
  { Atom.authors = [];
    categories = (match ch.category with
                  | None -> []
                  | Some c -> [ { Atom.term =c;
                                 scheme = None;  label = None} ]);
    contributors;
    generator = map_option ch.generator
                           (fun g -> { Atom.content = g;
                                    version = None;  uri = None });
    icon = None;
    id = Uri.to_string ch.link; (* FIXME: Best we can do? *)
    links = [ { Atom.href = ch.link;  rel = Atom.Related;
                type_media = Some "text/html";  hreflang = None;
                title = None;  length = None } ];
    logo = map_option ch.image (fun i -> i.url);
    rights = map_option ch.copyright (fun c -> (Atom.Text c: Atom.rights));
    subtitle = None;
    title = Atom.Text ch.title;
    updated;
    entries = List.map entry_of_item ch.items;
  }
