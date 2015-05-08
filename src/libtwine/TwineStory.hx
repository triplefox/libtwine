package libtwine;

import htmlparser.HtmlAttribute;
import htmlparser.HtmlDocument;
import htmlparser.HtmlNode;
import htmlparser.HtmlNodeElement;
import htmlparser.HtmlParser;

enum TwineLinkType {
	TLTPipe;
	TLTLeftArrow;
	TLTRightArrow;
	TLTNone;
}
 
enum TwinePassageToken {
	TPTBody(text : String);
	TPTLink(type : TwineLinkType, display : String, link : String, expression:String);
	TPTExpression(text : String);
}

enum TwinePassageLinkToken {
	TPLTBody(text : String);
	TPLTPipe;
	TPLTArrowLeft;
	TPLTArrowRight;
	TPLTBracketSeparator;
}

enum TwinePassageIntermediateToken {
	TPITBodyText(text : String);
	TPITOpenLink;
	TPITCloseLink;
	TPITFinal(tok : TwinePassageToken);
	TPITTripleABracketLeft;
	TPITTripleABracketRight;
	TPITDoubleABracketLeft;
	TPITDoubleABracketRight;
}

class TwinePassage
{
	public function new() { parse_warnings = []; }
	public var pid : Int;
	public var name : String;
	public var tags : Array<String>;
	public var position : Array<Int>;
	public var body : String;
	public var source : HtmlNodeElement;
	public var parse_warnings : Array<String>;
	
	public function tokenize() : Array<TwinePassageToken> {
		/* 
			Triplefox:
			The Twine editor's method is to use a lot of chained regular expressions, in this order:
				
				1. Arrow links
				[[display text->link]] format
				[[link<-display text]] format
				Regex will interpret the rightmost '->' and the leftmost '<-' as the divider.
		
				2. TiddlyWiki links
				[[display text|link]] format
				
				[[link]] format
				
				3. catch empty links, i.e. [[]]
				
				It doesn't try to deal with expressions or the other TiddlyWiki markup.
				
			My implementation uses a hand-written state machine that parses in multiple passes, "bottom-up" fashion.
			
			First it tokenizes various precedented character groupings like "double bracket left".
			It does the links first, then parses the inner parts of each link.
			Then, it returns to the top level and repeats the process for expressions.
			
			Finally, it reformats everything into a cleaned-up array of token types.
			
			The link parsing is a little bit less forgiving than Twine's original method; if it can't detect an exact pattern,
			it will just return the link content as one big string: content like [[Link->Link<-Link]] will fail in this way.
		*/
		var buildLookahead = function(a0 : String) : Array<Int> {
			var r0 = new Array<Int>();
			for (i0 in 0...a0.length) {
				r0.push(a0.charCodeAt(i0));
			}
			return r0;
		}
		var lookahead = function(content : String, start_idx : Int, token : Array<Int>) : Bool {
			var i0 = start_idx;
			var i1 = 0;
			while (i0 < content.length && i1 < token.length) {
				if (token[i1] != content.charCodeAt(i0)) return false;
				i0 += 1; i1 += 1;
			}
			return (i1 >= token.length);
		}
		var lookahead2 = function(content : Array<TwinePassageIntermediateToken>, start_idx : Int, 
			token : Array<TwinePassageIntermediateToken>) {
			var i0 = start_idx;
			var i1 = 0;
			while (i0 < content.length && i1 < token.length) {
				if (token[i1].getIndex() != content[i0].getIndex()) return false;
				i0 += 1; i1 += 1;
			}
			return (i1 >= token.length);
		}
		var lookahead3 = function(content : Array<TwinePassageLinkToken>,
			token : Array<TwinePassageLinkToken>) {
			var i0 = 0;
			if (content.length != token.length) return false;
			while (i0 < content.length && i0 < token.length) {
				if (token[i0].getIndex() != content[i0].getIndex()) return false;
				i0 += 1;
			}
			return (i0 >= token.length);
		}
		var la_openlink = buildLookahead("[[");
		var la_closelink = buildLookahead("]]");
		var la_linkpipe = buildLookahead("|");
		var la_linkarrowleft = buildLookahead("<-");
		var la_linkarrowright = buildLookahead("->");
		var la_linkbracketseparator = buildLookahead("][");
		var la_tripleabracketleft = buildLookahead("<<<");
		var la_tripleabracketright = buildLookahead(">>>");
		var la_doubleabracketleft = buildLookahead("<<");
		var la_doubleabracketright = buildLookahead(">>");
		
		var la2_expression = [TPITDoubleABracketLeft, TPITBodyText(null), TPITDoubleABracketRight];
		var la2_linkbody = [TPITOpenLink, TPITBodyText(null), TPITCloseLink];
		
		var la3_link = [TPLTBody(null)];
		var la3_setter = [TPLTBody(null), TPLTBracketSeparator, TPLTBody(null)];
		var la3_pipelink = [TPLTBody(null), TPLTPipe, TPLTBody(null)];
		var la3_leftalink = [TPLTBody(null), TPLTArrowLeft, TPLTBody(null)];
		var la3_rightalink = [TPLTBody(null), TPLTArrowRight, TPLTBody(null)];
		
		/* 0. find all double brackets (links). */
		var pass0 = new Array<TwinePassageIntermediateToken>();
		{
			var pass = pass0;
			var prevpass = [TPITBodyText(body)];
			for (tok in prevpass)
			{
				switch(tok)
				{
					case TPITBodyText(body):
						var curt = "";
						var i0 = 0;
						while (i0 < body.length) {
							if (lookahead(body, i0, la_openlink)) {
								pass.push(TPITBodyText(curt)); curt = "";
								pass.push(TPITOpenLink);
								i0 += la_openlink.length;
							}
							else if (lookahead(body, i0, la_closelink)) {
								pass.push(TPITBodyText(curt)); curt = "";
								pass.push(TPITCloseLink);
								i0 += la_closelink.length;
							}
							else {
								curt += body.charAt(i0);
								i0 += 1;
							}
						}
						if (curt.length > 0) pass.push(TPITBodyText(curt));
					default: pass.push(tok);
				}
			}
		}
		
		/* 1. parse open link, body, close link into a final link. */
		var pass1 = new Array<TwinePassageIntermediateToken>();
		{
			var pass = pass1;
			var prevpass = pass0;
			var i0 = 0;
			while (i0 < prevpass.length)
			{
				if (lookahead2(prevpass, i0, la2_linkbody)) {
					var body : String = prevpass[i0 + 1].getParameters()[0];
					/* a. link body -> link or setter bodies. */
					{
						var lpass = new Array<TwinePassageLinkToken>();
						{
							var curt = "";
							var i1 = 0;
							while (i1 < body.length) {
								if (lookahead(body, i1, la_linkbracketseparator)) {
									lpass.push(TPLTBody(curt)); curt = "";
									lpass.push(TPLTBracketSeparator);
									i1 += la_linkbracketseparator.length;
								}
								else {
									curt += body.charAt(i1);
									i1 += 1;
								}
							}
							if (curt.length > 0) lpass.push(TPLTBody(curt));
						}
						
						/* parse the inner part of the link: the pipe or arrow stuff. */
						var linkInnerParser = function(body : String) : {
							display : String, link : String, type : TwineLinkType
						} {
							/* 0. split up tokens some more. */
							var pass = new Array<TwinePassageLinkToken>();
							{
								var curt = "";
								var i0 = 0;
								while (i0 < body.length) {
									if (lookahead(body, i0, la_linkarrowleft)) {
										pass.push(TPLTBody(curt)); curt = "";
										pass.push(TPLTArrowLeft);
										i0 += la_linkarrowleft.length;
									}
									else if (lookahead(body, i0, la_linkarrowright)) {
										pass.push(TPLTBody(curt)); curt = "";
										pass.push(TPLTArrowRight);
										i0 += la_linkarrowright.length;
									}
									else if (lookahead(body, i0, la_linkpipe)) {
										pass.push(TPLTBody(curt)); curt = "";
										pass.push(TPLTPipe);
										i0 += la_linkpipe.length;
									}
									else {
										curt += body.charAt(i0);
										i0 += 1;
									}
								}
								if (curt.length > 0) pass.push(TPLTBody(curt));
							}
							
							/* 1. determine link type and return result. */
							if (lookahead3(pass, la3_pipelink)) {
								return {
									display:pass[0].getParameters()[0],
									link:pass[2].getParameters()[0],
									type:TLTPipe
								};
							}
							else if (lookahead3(pass, la3_leftalink)) {
								return {
									display:pass[2].getParameters()[0],
									link:pass[0].getParameters()[0],
									type:TLTLeftArrow
								};
							}
							else if (lookahead3(pass, la3_rightalink)) {
								return {
									display:pass[0].getParameters()[0],
									link:pass[2].getParameters()[0],
									type:TLTRightArrow
								};
							}
							else {
								return {
									display:null,
									link:body,
									type:TLTNone
								};
							}
							
						};
						
						{ /* combine inner with setter */
							var linkDisplay : String = null;
							var linkLink : String = null;
							var linkSetter : String = null;
							var linkType = TLTNone;
							if (lookahead3(lpass, la3_setter)) /* b0. setter and link */
							{
								var result = linkInnerParser(lpass[0].getParameters()[0]);
								linkDisplay = result.display;
								linkLink = result.link;
								linkType = result.type;
								linkSetter = lpass[2].getParameters()[0];
							}
							else /* b1. link only */
							{
								var result = linkInnerParser(lpass[0].getParameters()[0]);
								linkDisplay = result.display;
								linkLink = result.link;
								linkType = result.type;
							}
							pass.push(TPITFinal(TPTLink(linkType,linkDisplay,linkLink,linkSetter)));
						}
					}
					
					i0 += la2_linkbody.length;
				}
				else {
					pass.push(prevpass[i0]);
					i0 += 1;
				}
			}
		}
		
		/* 2. find all triple angle brackets. */
		var pass2 = new Array<TwinePassageIntermediateToken>();
		{
			var pass = pass2;
			var prevpass = pass1;
			for (tok in prevpass)
			{
				switch(tok)
				{
					case TPITBodyText(body):
						var curt = "";
						var i0 = 0;
						while (i0 < body.length) {
							if (lookahead(body, i0, la_tripleabracketleft)) {
								pass.push(TPITBodyText(curt)); curt = "";
								pass.push(TPITTripleABracketLeft);
								i0 += la_tripleabracketleft.length;
							}
							else if (lookahead(body, i0, la_tripleabracketright)) {
								pass.push(TPITBodyText(curt)); curt = "";
								pass.push(TPITTripleABracketRight);
								i0 += la_tripleabracketright.length;
							}
							else {
								curt += body.charAt(i0);
								i0 += 1;
							}
						}
						if (curt.length > 0) pass.push(TPITBodyText(curt));
					default: pass.push(tok);
				}
			}
		}
		
		/* 3. find all double angle brackets. */
		var pass3 = new Array<TwinePassageIntermediateToken>();
		{
			var pass = pass3;
			var prevpass = pass2;
			for (tok in prevpass)
			{
				switch(tok)
				{
					case TPITBodyText(body):
						var curt = "";
						var i0 = 0;
						while (i0 < body.length) {
							if (lookahead(body, i0, la_doubleabracketleft)) {
								pass.push(TPITBodyText(curt)); curt = "";
								pass.push(TPITDoubleABracketLeft);
								i0 += la_doubleabracketleft.length;
							}
							else if (lookahead(body, i0, la_doubleabracketright)) {
								pass.push(TPITBodyText(curt)); curt = "";
								pass.push(TPITDoubleABracketRight);
								i0 += la_doubleabracketright.length;
							}
							else {
								curt += body.charAt(i0);
								i0 += 1;
							}
						}
						if (curt.length > 0) pass.push(TPITBodyText(curt));
					default: pass.push(tok);
				}
			}
		}

		/* 3. parse double angle bracket left, body, double angle brack right into TPITExpression. */
		var pass4 = new Array<TwinePassageIntermediateToken>();
		{
			var pass = pass4;
			var prevpass = pass3;
			var i0 = 0;
			while (i0 < prevpass.length)
			{
				if (lookahead2(prevpass, i0, la2_expression)) {
					pass.push(TPITFinal(TPTExpression(prevpass[i0 + 1].getParameters()[0])));
					i0 += la2_expression.length;
				}
				else {
					pass.push(prevpass[i0]);
					i0 += 1;
				}
			}
		}
		
		/* 4. Merge leftover results into the final TwinePassageTokens. */
		var pass5 = new Array<TwinePassageToken>();
		{
			var pass = pass5;
			var prevpass = pass4;
			var i0 = 0;
			var curbody = "";
			var flushBody = function() {
				if (curbody.length > 0) {
					pass.push(TPTBody(curbody)); curbody = "";
				}
			};
			var pushBody = function(body : String) {
				curbody += body;
			};
			
			{
				for (n0 in prevpass)
				{
					switch(n0)
					{
						case TPITFinal(tok): flushBody(); pass.push(tok);
						case TPITBodyText(body): pushBody(body);
						case TPITOpenLink: pushBody("[[");
						case TPITCloseLink: pushBody("]]");
						case TPITDoubleABracketLeft: pushBody("<<");
						case TPITDoubleABracketRight: pushBody(">>");
						case TPITTripleABracketLeft: pushBody("<<<");
						case TPITTripleABracketRight: pushBody(">>>");
					}
				}
				flushBody();
			}
			return pass;
		}
	}
	
	public function toHtmlNodeElement() : HtmlNodeElement {
		var ele = new HtmlNodeElement("tw-passagedata", [
			new HtmlAttribute("pid", Std.string(pid), '"'),
			new HtmlAttribute("position", position.join(","), '"'),
			new HtmlAttribute("name", StringTools.htmlEscape(name, true), '"'),
			new HtmlAttribute("tags", StringTools.htmlEscape(tags.join(" "), true), '"')
		]
		);
		ele.setInnerText(body);
		return ele;
	}
	
	public static function detokenize(tok : Array<TwinePassageToken>) {
		var r0 = "";
		for (t0 in tok) {
			switch(t0) {
				case TPTBody(text):
					r0 += text;
				case TPTLink(type, display, link, expression):
					r0 += "[[";
					switch(type) {
						case TLTPipe:
							r0 += display; r0 += "|"; r0 += link;
						case TLTLeftArrow:
							r0 += link; r0 += "<-"; r0 += display;
						case TLTRightArrow:
							r0 += display; r0 += "->"; r0 += link;
						case TLTNone:
							r0 += link;
					}
					if (expression != null && expression.length > 0) {
						r0 += "]["; r0 += expression; r0 += "]]";						
					}
					else r0 += "]]";
				case TPTExpression(text):
					r0 += "<<" + text + ">>";
			}
		}
		return r0;
	}
	
}

class TwineStory
{
	public function new () { parse_warnings = []; passagedata = []; }
	public var name : String;
	public var startnode : Int;
	public var creator : String;
	public var creator_version : String;
	public var ifid : String;
	public var format : String;
	public var options : String;
	public var style : HtmlNodeElement;
	public var script : HtmlNodeElement;
	public var passagedata : Array<TwinePassage>;
	public var doc_source : HtmlDocument;
	public var story_source : HtmlNodeElement;
	public var parse_warnings : Array<String>;
	
	/*
	 * Twine documentation underspecifies tags, but they appear to use ordinary HTML escaping, and remap spaces to
	 * "-" characters. TwineStory automatically unescapes the HTML to work with the content, and then validates
	 * tags when serializing.
	 * */
	public static function escapeTag(s0 : String)
	{
		return StringTools.replace(s0, " ", "-");
	}
	
	public static function validateTag(s0 : String) { 
		if (s0.indexOf(" ") >= 0) throw 'tag \"${s0}\" contains a space: use escapeTag() to auto-remap it.';
	}
	
	public function tagSearch() {
		var r0 = new Map<String, Array<TwinePassage>>();
		for (p0 in passagedata) {
			for (t0 in p0.tags)
			{
				if (r0.exists(t0)) { r0.get(t0).push(p0); }
				else { r0.set(t0, [p0]); }
			}
		}
		return r0;
	}
	
	public function titleSearch() {
		var r0 = new Map<String, TwinePassage>();
		for (p0 in passagedata) {
			r0.set(p0.name, p0);
		}
		return r0;
	}
	
	public function findPassage(name : String) {
		return titleSearch().get(name);
	}
	
	public function findTag(tag : String) {
		return tagSearch().get(tag);
	}
	
	public function passageContent(passage : TwinePassage) {
		// return tokenized passage, links, expressions, link mapping
		var tok = passage.tokenize();
		var expr : Array<String> = [];
		var links : Array<{type:TwineLinkType,display:String,link:String,expression:String}> = [];		
		for (n0 in tok)
		{
			switch(n0)
			{
				case TPTBody(text):
				case TPTExpression(text):
					expr.push(text);
				case TPTLink(type, display, link, expression):
					links.push( { type:type, display:display, link:link, expression:expression } );
			}
		}
		return {
			passage:passage,
			tokens:tok,
			expressions:expr,
			links:links
		};
	}
	
	public function allLinks() {
		var inbound = new Map<String, Array<String>>();
		var outbound = new Map<String, Array<String>>();
		for (p0 in passagedata)
		{
			for (l0 in passageContent(p0).links)
			{
				{
					var l1 : Array<String>;
					if (outbound.exists(p0.name)) l1 = outbound.get(p0.name); else 
						{ l1 = new Array(); outbound.set(p0.name, l1); }
					l1.push(l0.link);
				}
				
				{
					var l1 : Array<String>;
					if (inbound.exists(l0.link)) l1 = inbound.get(l0.link); else 
						{ l1 = new Array(); inbound.set(l0.link, l1); }
					l1.push(p0.name);
				}
			}
		}
		return { inbound:inbound, outbound:outbound };
	}
	
	private static var CHARS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".split("");	
	/**
	 * generate RFC4122, version 4 ID
	 * example "92329D39-6F5C-4520-ABFC-AAB64544E172"
	 * Triplefox: This code has been tainted a bit to just use Math.random() since it's not used in a secure application.
	 * Original: https://github.com/rjanicek/janicek-core-haxe/blob/master/src/co/janicek/core/math/UUID.hx
	 */
	public static function uuid() {
		var chars = CHARS, uuid = new Array(), rnd=0, r;
		for (i in 0...36) {
			if (i==8 || i==13 ||  i==18 || i==23) {
				uuid[i] = "-";
			} else if (i==14) {
				uuid[i] = "4";
			} else {
				if (rnd <= 0x02) rnd = 0x2000000 + Std.int((Math.random() * 0x1000000)) | 0;
				r = rnd & 0xf;
				rnd = rnd >> 4;
				uuid[i] = chars[(i == 19) ? (r & 0x3) | 0x8 : r];
			}
		}
		return uuid.join("");
	}
	
	public function applyUuid() {
		for (p0 in passagedata) {
			var add = true;
			for (t0 in p0.tags) {
				if (StringTools.startsWith(t0, "uuid-")) {
					add = false; break;
				}
			}
			if (add) {
				p0.tags.push("uuid-"+uuid());
			}
		}		
	}
	
	public static function parsePassage(n0 : HtmlNodeElement) {
		var p0 = new TwinePassage();
		p0.source = n0;
		for (a0 in n0.attributes)
		{
			switch (a0.name)
			{
				case "pid": p0.pid = Std.parseInt(a0.value);
				case "name": p0.name = a0.value;
				case "tags": if (a0.value.length == 0) { p0.tags = []; }
					else { p0.tags = [for (t0 in a0.value.split(" ")) StringTools.htmlUnescape(t0)]; }
				case "position": p0.position = [for (t0 in a0.value.split(",")) Std.parseInt(t0)];
				default: p0.parse_warnings.push("unknown-attribute:"+a0.toString());
			}
		}
		p0.body = StringTools.htmlUnescape(n0.innerHTML);
		return p0;
	}
	
	public static function parseString(s0 : String) {
		return parseHtmlDocument(new HtmlDocument(s0));
	}
	
	public static function parseHtmlDocument(htm : HtmlDocument)
	{
		var story = new TwineStory();
		story.doc_source = htm;
		var hstory = htm.find("tw-storydata"); /* there is a "tw-story" but it has no content? */
		for (n0 in hstory)
		{
			story.story_source = n0;
			for (a0 in n0.attributes)
			{
				switch(a0.name)
				{
					case "name": story.name = a0.value;
					case "startnode": story.startnode = Std.parseInt(a0.value);
					case "creator": story.creator = a0.value;
					case "creator-version": story.creator_version = a0.value;
					case "ifid": story.ifid = a0.value;
					case "format": story.format = a0.value;
					case "options": story.options = a0.value;
					default: story.parse_warnings.push("unknown-attribute:"+a0.toString());
				}
			}
			for (c0 in n0.children)
			{
				if (c0.name == "style") {
					story.style = c0;
				}
				else if (c0.name == "script") {
					story.script = c0;
				}
				else if (c0.name == "tw-passagedata") {
					story.passagedata.push(parsePassage(c0));
				}
				else {
					story.parse_warnings.push("unknown-node:"+c0.toString());
				}
			}
		}		
		return story;
	}
	
	public function toHtmlDocument() : HtmlDocument {
		/* 1. copy doc_source
		 * 2. replace story_source with the new node */
		
		var outdoc = new HtmlDocument(doc_source.toString());
		var hstory = outdoc.find("tw-storydata");
		for (n0 in hstory) {
			n0.setInnerText("");
			n0.attributes = [
				new HtmlAttribute("name", StringTools.htmlEscape(name, true), '"'),
				new HtmlAttribute("startnode", Std.string(startnode), '"'),
				new HtmlAttribute("creator", StringTools.htmlEscape(creator, true), '"'),
				new HtmlAttribute("creator-version", StringTools.htmlEscape(creator_version, true), '"'),
				new HtmlAttribute("ifid", StringTools.htmlEscape(ifid, true), '"'),
				new HtmlAttribute("format", StringTools.htmlEscape(format, true), '"'),
				new HtmlAttribute("options", StringTools.htmlEscape(options, true), '"'),
			];
			n0.addChild(style);
			n0.addChild(script);
			for (p0 in passagedata) {
				n0.addChild(p0.toHtmlNodeElement());
			}
		}
		return outdoc;
	}
	
}

