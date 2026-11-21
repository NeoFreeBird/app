#import "../HookHelpers.h"

static const void* KeepReplyInWebViewKey = &KeepReplyInWebViewKey;
static const void* ReplyWebViewDismissingKey = &ReplyWebViewDismissingKey;

// Injected into the reply webview: hooks fetch/XHR to capture the new post's ID from
// the web CreateTweet response, since there's no native completion callback to read.
static NSString* const ReplyCaptureScript =
    @"(function(){"
     "if(window.__bhtReplyHook)return;window.__bhtReplyHook=true;"
     "var save=function(j){try{if(j&&j.data){"
     "var "
     "r=(j.data.create_tweet&&j.data.create_tweet.tweet_results&&j.data.create_tweet.tweet_results."
     "result)||"
     "(j.data.notetweet_create&&j.data.notetweet_create.tweet_results&&j.data.notetweet_create."
     "tweet_results.result);"
     "if(r&&r.rest_id)sessionStorage.setItem('__bhtNewReply',String(r.rest_id));}}catch(e){}};"
     "var isCreate=function(u){return typeof u==='string'&&u.indexOf('CreateTweet')!==-1;};"
     "var of=window.fetch;"
     "if(of){window.fetch=function(){var a=arguments;var u=(a[0]&&a[0].url)||a[0];"
     "return "
     "of.apply(this,a).then(function(res){try{if(isCreate(u))res.clone().json().then(save).catch("
     "function(){});}catch(e){}return res;});};}"
     "var oo=XMLHttpRequest.prototype.open;var os=XMLHttpRequest.prototype.send;"
     "XMLHttpRequest.prototype.open=function(m,u){this.__bhtURL=u;return "
     "oo.apply(this,arguments);};"
     "XMLHttpRequest.prototype.send=function(){var x=this;try{if(isCreate(x.__bhtURL)){"
     "x.addEventListener('load',function(){try{save(JSON.parse(x.responseText));}catch(e){}});}}"
     "catch(e){}return os.apply(this,arguments);};"
     "})();";

// Reads and clears the reply ID stashed by the capture script.
static NSString* const ReplyReadScript =
    @"(function(){var "
    @"v=sessionStorage.getItem('__bhtNewReply')||'';sessionStorage.removeItem('__bhtNewReply');"
    @"return v;})();";

TFNTwitterStatus* statusFromObject(id object);
void showPostSentAlert(NSString* statusID);
BOOL openAuthenticatedTweetWebView(NSString* statusID);
