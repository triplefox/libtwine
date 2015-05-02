package;

import libtwine.TwineStory;
import neko.Lib;
import sys.io.File;

/**
 * ...
 * @author nblah
 */

class Main 
{
	
	static function main() 
	{
		
		/* load my twine story... */
		var fc = File.getContent("Test.html");
		var story = libtwine.TwineStory.parseString(fc);
		
		//trace(story.passageLinks(story.passagedata[0]));
		for (p0 in story.passagedata)
		{
			var pc = story.passageContent(p0);
			//trace([pc.passage.name, pc.links]);
		}
		
		{
			var al = story.allLinks();
			for (ib in al.outbound.keys())
			{
				trace([ib, [for (ic in al.outbound.get(ib)) ic]]);
			}
		}
		
	}
	
}