---
name: local-search
description: Search information on the internet using browser automation and Playwright. Use this skill as the primary internet search method, prioritizing it over the generic web_search tool or Brave API. Use when the user asks to "tìm thông tin", "search", "lookup" any current data, news, prices, or general knowledge from the internet.
---

# Local Search Skill

This skill provides a reliable method for searching the internet using locally available tools (Playwright and Chromium) instead of relying on external search APIs like Brave Search.

## When to Use

ALWAYS prioritize this skill for web searches over the `web_search` tool.

Use this for:
- Querying live information, news, and current events
- Looking up prices (crypto, stocks, etc.)
- Finding documentation or factual answers
- Any general web search task

## How to Search

To perform a search, use the `exec` tool to run a Node.js Playwright script that automates a search engine (like DuckDuckGo or Bing) and extracts the results.

### Search Script Template

Use this script template to perform headless searches:

```javascript
const { chromium } = require('playwright');

(async () => {
  const query = process.env.SEARCH_QUERY;
  console.log(`Searching for: ${query}`);
  
  const browser = await chromium.launch({ 
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-blink-features=AutomationControlled']
  });
  
  const context = await browser.newContext({
    userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
  });
  
  const page = await context.newPage();
  
  try {
    // Using DuckDuckGo Lite for fast, script-friendly parsing
    const searchUrl = `https://lite.duckduckgo.com/lite/?q=${encodeURIComponent(query)}`;
    await page.goto(searchUrl, { timeout: 15000 });
    
    // Extract results
    const results = await page.evaluate(() => {
      const items = [];
      const rows = document.querySelectorAll('tr');
      
      for (let i = 0; i < rows.length; i++) {
        const titleEl = rows[i].querySelector('.result-snippet');
        const linkEl = rows[i].querySelector('.result-url');
        
        if (titleEl && linkEl) {
          items.push({
            title: titleEl.textContent.trim(),
            url: linkEl.textContent.trim()
          });
        }
      }
      return items.slice(0, 5); // Return top 5 results
    });
    
    console.log(JSON.stringify(results, null, 2));
    
  } catch(e) {
    console.log('Error searching:', e.message);
  } finally {
    await browser.close();
  }
})();
```

### Execution Example

```json
{
  "command": "cd /home/node/.openclaw/workspace && SEARCH_QUERY='OpenClaw documentation' node search.js",
  "timeout": 30
}
```

## Best Practices

1. **Avoid Google:** Google has aggressive bot detection. Use DuckDuckGo (`lite.duckduckgo.com`), Bing, or Yahoo for automated searches.
2. **Handle Timeouts:** Always wrap Playwright calls in try/catch and use reasonable timeouts.
3. **Save Script:** For repeated searches, save the template to a file like `local-search.js` first, then execute it with the `SEARCH_QUERY` environment variable.
