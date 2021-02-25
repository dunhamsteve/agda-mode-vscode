open Belt
open React

// <Text> represents a mixed array of Strings & Locations
module Text = {
  module Segment = {
    type t =
      | PlainText(string, option<array<string>>)
      | Icon(string)
      | Link(string, option<array<string>>, bool, bool, Common.Link.t)
      | Location(Common.AgdaRange.t, bool)

    open! Json.Decode
    open Util.Decode

    let decode: decoder<t> = sum(x =>
      switch x {
      | "PlainText" =>
        Contents(
          pair(string, optional(array(string))) |> map(((s, className)) => PlainText(s, className)),
        )
      | "Icon" => Contents(string |> map(kind => Icon(kind)))
      | "Link" =>
        Contents(
          tuple5(string, optional(array(string)), bool, bool, Common.Link.decode) |> map(((
            s,
            className,
            jump,
            hover,
            link,
          )) => Link(s, className, jump, hover, link)),
        )
      | "Location" =>
        Contents(pair(Common.AgdaRange.decode, bool) |> map(((loc, abbr)) => Location(loc, abbr)))
      | tag => raise(DecodeError("[Component.Text] Unknown constructor: " ++ tag))
      }
    )

    open! Json.Encode
    let encode: encoder<t> = x =>
      switch x {
      | PlainText(s, className) =>
        object_(list{
          ("tag", string("PlainText")),
          ("contents", (s, className) |> pair(string, nullable(array(string)))),
        })
      | Icon(kind) => object_(list{("tag", string("Icon")), ("contents", kind |> string)})
      | Link(s, className, jump, hover, link) =>
        object_(list{
          ("tag", string("Link")),
          (
            "contents",
            (s, className, jump, hover, link) |> Util.Encode.tuple5(
              string,
              nullable(array(string)),
              bool,
              bool,
              Common.Link.encode,
            ),
          ),
        })
      | Location(loc, abbr) =>
        object_(list{
          ("tag", string("Location")),
          ("contents", (loc, abbr) |> pair(Common.AgdaRange.encode, bool)),
        })
      }
  }
  type t = Text(array<Segment.t>)
  let toSegments = x =>
    switch x {
    | Text(xs) => xs
    }
  let concatMany = xs => Text(xs->Array.map(toSegments)->Array.concatMany)
  // smart constructors
  let empty = Text([])
  let plainText = (~className=?, s) => Text([Segment.PlainText(s, className)])
  let link = (text, ~jump=true, ~hover=false, ~className=?, loc) => Text([
    Segment.Link(text, className, jump, hover, Common.Link.ToRange(loc)),
  ])
  let hole = (text, ~jump=true, ~hover=false, ~className=?, holeIndex) => Text([
    Segment.Link(text, className, jump, hover, Common.Link.ToHole(holeIndex)),
  ])
  let location = (location, abbr) => Text([Segment.Location(location, abbr)])
  // from string
  let parse = raw =>
    raw
    ->Js.String.splitByRe(
      %re("/([^\\(\\)\\s]+\\:(?:\\d+\\,\\d+\\-\\d+\\,\\d+|\\d+\\,\\d+\\-\\d+))/"),
      _,
    )
    ->Array.keepMap(x => x)
    ->Array.mapWithIndex((i, token) =>
      switch mod(i, 2) {
      | 1 =>
        token
        ->Common.AgdaRange.parse
        ->Option.mapWithDefault(Segment.PlainText(token, None), x => Segment.Location(x, false))
      | _ => PlainText(token, None)
      }
    )
    ->(xs => Text(xs))

  @react.component
  let make = (~text: t) => {
    let Text(segments) = text
    <span>
      {segments
      ->Array.mapWithIndex((i, x) =>
        switch x {
        | PlainText(plainText, None) => string(plainText)
        | PlainText(plainText, Some(className)) =>
          <span key={string_of_int(i)} className={className->Array.joinWith(" ", x => x)}>
            {string(plainText)}
          </span>
        | Icon(kind) => <div className={"codicon codicon-" ++ kind} />
        | Link(text, None, jump, hover, target) =>
          <Component__Link key={string_of_int(i)} jump hover target>
            {string(text)}
          </Component__Link>
        | Link(text, Some(className), jump, hover, target) =>
          let className = className->List.fromArray
          <Component__Link key={string_of_int(i)} jump hover className target>
            {string(text)}
          </Component__Link>
        | Location(location, true) =>
          <Component__Link key={string_of_int(i)} jump=true target=Common.Link.ToRange(location)>
            <div className="codicon codicon-link" />
          </Component__Link>
        | Location(location, false) =>
          <Component__Link key={string_of_int(i)} jump=true target=Common.Link.ToRange(location)>
            <div className="codicon codicon-link" /> {string(Common.AgdaRange.toString(location))}
          </Component__Link>
        }
      )
      ->React.array}
    </span>
  }

  open! Json.Decode
  let decode: decoder<t> = array(Segment.decode) |> map(segments => Text(segments))
  open! Json.Encode
  let encode: encoder<t> = x =>
    switch x {
    | Text(segments) => segments |> array(Segment.encode)
    }
}

module Item = {
  type t =
    | Labeled(string, string, Text.t, option<string>) // label // style // body // raw string
    | Unlabeled(Text.t, option<string>) // body // raw string

  let plainText = s => Unlabeled(Text.plainText(s), None)

  @react.component
  let make = (~item: t) =>
    switch item {
    | Labeled(label, style, text, _raw) =>
      <li className={"labeled-item " ++ style}>
        <div className="item-label"> {string(label)} </div>
        <div className="item-content"> <Text text /> </div>
      </li>
    | Unlabeled(text, _raw) =>
      <li className="unlabeled-item"> <div className="item-content"> <Text text /> </div> </li>
    }

  open! Json.Decode
  open Util.Decode

  let decode: decoder<t> = sum(x =>
    switch x {
    | "Labeled" =>
      Contents(
        tuple4(string, string, Text.decode, optional(string)) |> map(((
          label,
          style,
          text,
          raw,
        )) => Labeled(label, style, text, raw)),
      )
    | "Unlabeled" =>
      Contents(pair(Text.decode, optional(string)) |> map(((text, raw)) => Unlabeled(text, raw)))
    | tag => raise(DecodeError("[Component.Item] Unknown constructor: " ++ tag))
    }
  )

  open! Json.Encode
  let encode: encoder<t> = x =>
    switch x {
    | Labeled(label, style, text, raw) =>
      object_(list{
        ("tag", string("Labeled")),
        (
          "contents",
          (label, style, text, raw) |> tuple4(string, string, Text.encode, nullable(string)),
        ),
      })
    | Unlabeled(text, raw) =>
      object_(list{
        ("tag", string("Unlabeled")),
        ("contents", (text, raw) |> pair(Text.encode, nullable(string))),
      })
    }
}
