import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Cycles "mo:base/ExperimentalCycles";
import Error "mo:base/Error";
import Int "mo:base/Int";
import List "mo:base/List";
import Nat "mo:base/Nat";
import Option "mo:base/Option";
import R "mo:base/Result";
import Text "mo:base/Text";
import Time "mo:base/Time";
import AssocList "mo:base/AssocList";

/// - Plug&Play simple example:
///
/// import HttpAgent "./http_agent";
///
/// var httpAgent : ?HttpAgent.HttpAgent = null;
/// public query func http_transform(raw : HttpAgent.TransformArgs) : async HttpAgent.HttpResponsePayload = async U.require(httpAgent).transform(raw);
/// httpAgent := ?HttpAgent.HttpAgent(http_transform, [], null);
///
/// let resp = await* U.require(httpAgent).simpleGet(
///   "api.exchange.coinbase.com",
///   "products/ICP-USD/candles",
///   [{ name = "accept"; value = "application/json" }],
///   null,
/// );
///
///
/// - Preserve cache in stable memory:
///
/// stable var httpCache : HttpAgent.HttpCache = null;
/// httpAgent := ?HttpAgent.HttpAgent(http_transform, [], httpCache);
///
/// system func preupgrade() {
///   switch (httpAgent) {
///     case (?a) httpCache := a.share();
///     case (null) {};
///   };
/// };
///
///
/// - Use custom transformers:
///
/// httpAgent := ?HttpAgent.HttpAgent(
///   http_transform,
///   [("my_transformer0", func (raw) = {...}), ("my_transformer1", func (raw) = {...})],
///   null
/// );
///
/// let resp = await* U.require(httpAgent).simpleGet(
///   "api.exchange.coinbase.com",
///   "products/ICP-USD/candles",
///   [],
///   ?"my_transformer0",
/// );
module {

  public type HttpHeader = {
    name : Text;
    value : Text;
  };

  type HttpOutgoingRequestArgs = {
    url : Text;
    max_response_bytes : ?Nat64;
    headers : [HttpHeader];
    body : ?[Nat8];
    method : { #get; #post; #head };
    transform : ?{
      function : shared query { response : HttpResponsePayload; context : Blob } -> async HttpResponsePayload;
      context : Blob;
    };
  };

  public type HttpResponsePayload = {
    status : Nat;
    headers : [HttpHeader];
    body : [Nat8];
  };

  type IC = actor {
    http_request : HttpOutgoingRequestArgs -> async HttpResponsePayload;
  };

  public type TextResponse = {
    status : Nat;
    body : Text;
  };

  public type TransformArgs = { response : HttpResponsePayload; context : Blob };
  type SimpleGetArgs = (host : Text, path : Text, headers : [HttpHeader], transformer : ?Text);

  public type HttpCache = AssocList.AssocList<Text, (Nat, R.Result<TextResponse, Text>)>;

  public class HttpAgent(
    transformQuery : shared query TransformArgs -> async HttpResponsePayload,
    transformers : [(Text, HttpResponsePayload -> HttpResponsePayload)],
    cache_ : HttpCache,
  ) {

    var httpCache : HttpCache = cache_;

    public func share() : HttpCache = httpCache;

    func defaultTransformer(raw : HttpResponsePayload) : HttpResponsePayload = {
      status = raw.status;
      body = raw.body;
      headers = [];
    };

    public func transform(raw : TransformArgs) : HttpResponsePayload {
      let ??transformerKey : ??Text = from_candid (raw.context) else return defaultTransformer(raw.response);
      let ?(_, transformer) = Array.find<(Text, HttpResponsePayload -> HttpResponsePayload)>(transformers, func(k, t) = k == transformerKey) else return defaultTransformer(raw.response);
      transformer(raw.response);
    };

    // simple get request which returns text data
    // example: await* HTTP.simpleGet("httpbin.org", "get", [{ name = "accept"; value = "application/json"; }]. null);
    public func simpleGet((host, path, headers, transform) : SimpleGetArgs) : async* TextResponse {
      let ic : IC = actor ("aaaaa-aa");
      let url = "https://" # host # "/" # path;

      let http_request : HttpOutgoingRequestArgs = {
        url = url;
        max_response_bytes = null;
        headers = headers;
        body = null;
        method = #get;
        transform = ?{
          function = transformQuery;
          context = to_candid (transform);
        };
      };
      Cycles.add<system>(230_949_972_000);
      let resp = await ic.http_request(http_request);
      {
        status = resp.status;
        body = resp.body |> Blob.fromArray(_) |> Text.decodeUtf8(_) |> Option.get(_, debug_show resp.body);
      };
    };

    // a wrapper around get request which caches responses
    public func simpleGetWithCache(cacheTTL : Nat, args : SimpleGetArgs) : async* R.Result<TextResponse, Text> {
      let now = Time.now() |> Int.abs(_);
      let cacheKey = args.0 # "/" # args.1;
      var updatedCache : HttpCache = List.nil();
      var cachedResp : ?R.Result<TextResponse, Text> = null;
      for ((key, (expiresAt, resp)) in List.toIter(httpCache)) {
        if (expiresAt > now) {
          updatedCache := List.push<(Text, (Nat, R.Result<TextResponse, Text>))>((key, (expiresAt, resp)), updatedCache);
          if (key == cacheKey) {
            cachedResp := ?resp;
          };
        };
      };
      let ret = switch (cachedResp) {
        case (?r) r;
        case (null) {
          let r = try {
            #ok(await* simpleGet(args));
          } catch (err) {
            #err(Error.message(err));
          };
          updatedCache := List.push<(Text, (Nat, R.Result<TextResponse, Text>))>((cacheKey, (now + cacheTTL, r)), updatedCache);
          r;
        };
      };
      httpCache := updatedCache;
      ret;
    };

  };

};
