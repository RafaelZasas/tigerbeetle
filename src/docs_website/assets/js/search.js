let pages = [];
let sections = [];

const searchInput = document.querySelector("input[type=search]");
const searchResults = document.querySelector(".search-results");
const searchHotkey = document.querySelector(".search-container>.hotkey");
const searchClearButton = document.querySelector(".search-container>.clear-button");

async function init() {
  const response = await fetch(urlPrefix + "/search-index.json");
  pages = await response.json();
  const parser = new DOMParser();
  pages.forEach((page, pageIndex) => {
    const doc = parser.parseFromString(page.html, "text/html");
    const body = doc.querySelector("body");

    let currentSection;
    for (const child of body.children) {
      const anchor = child.querySelector(".anchor");
      if (anchor) {
        const title = anchor.innerText.replace(/\n/g, " ");
        if (!page.title) page.title = title;
        currentSection = {
          pageIndex,
          title,
          path: page.path,
          hash: anchor.hash,
          text: title,
        };
        sections.push(currentSection);
      } else if (currentSection) {
        currentSection.text += " " + child.innerText.replace(/\n/g, " ");
      }
    }
  });

  if (searchInput.value) onSearchInput(); // Repeat search once the index is fetched.
}

init();

function onSearchInput() {
  const results = search(searchInput.value);
  const groups = [];
  let currentGroup;
  for (const result of results) {
    if (!currentGroup || currentGroup.pageIndex !== result.section.pageIndex) {
      currentGroup = { pageIndex: result.section.pageIndex, results: [] };
      groups.push(currentGroup);
    }
    currentGroup.results.push(result);
  }
  const highlightQuery = `?highlight=${encodeURIComponent(searchInput.value)}`
  searchResults.replaceChildren();
  for (const group of groups) {
    const menuHead = document.createElement("div");
    searchResults.appendChild(menuHead);
    menuHead.classList.add("item");
    menuHead.classList.add("menu-head");
    menuHead.classList.add("expanded");
    menuHead.innerText = pages[group.pageIndex].title;
    menuHead.addEventListener("click", ev => {
      if (ev.target == menuHead) menuHead.classList.toggle("expanded");
    })
    const menu = document.createElement("div");
    searchResults.appendChild(menu);
    menu.classList.add("menu");
    for (const result of group.results) {
      const item = document.createElement("div");
      menu.appendChild(item);
      item.classList.add("item");
      const a = document.createElement("a");
      item.appendChild(a);
      a.href = urlPrefix + "/" + result.section.path + "/" + highlightQuery + result.section.hash;
      a.innerHTML = result.context;
      a.pageIndex = result.section.pageIndex;
    }
  }

  searchClearButton.style.display = searchInput.value === "" ? "none" : "block";
}

function search(term) {
  if (term.length === 0) return [];
  const escapedTerm = term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const regex = new RegExp(escapedTerm, 'gi');
  let hits = [];
  for (const section of sections) {
    const match = regex.exec(section.text);
    if (match) {
      const firstIndex = match.index;
      const count = section.text.match(regex).length;
      hits.push({ firstIndex, count, section });
    }
  }
  hits.forEach(hit => hit.context = makeContext(hit.section.text, hit.firstIndex, term.length));
  return hits;
}

function makeContext(text, i, length, windowSize = 40) {
  const highlight = text.slice(i, i + length);

  let contextLeft = "";
  let i0 = Math.max(0, i - windowSize / 2);
  if (i0 > 0) contextLeft = "...";
  while (i0 > 0 && text[i0] !== ' ') i0--;
  contextLeft = contextLeft + text.slice(i0, i).trimLeft();

  let contextRight = "";
  let i1 = Math.min(text.length, i + length + windowSize / 2);
  if (i1 < text.length) contextRight = "...";
  while (i1 < text.length && text[i1] !== ' ') i1++;
  contextRight = text.slice(i + length, i1).trimRight() + contextRight;

  return `${escapeHtml(contextLeft)}<strong>${escapeHtml(highlight)}</strong>${escapeHtml(contextRight)}`;
}

function select(result) {
  result.classList.add("selected");
  scrollIntoViewIfNeeded(result);
  const page = pages[result.pageIndex];
  document.querySelector("article>.content").innerHTML = page.html;
  window.history.pushState({}, "", result.href);
  document.title = "TigerBeetle Docs | " + page.title;
  const anchor = document.querySelector(window.location.hash);
  anchor.scrollIntoView();
  highlightText(searchInput.value);
}

function selectNextResult() {
  const selected = searchResults.querySelector(".selected");
  if (selected) {
    selected.classList.remove("selected");
    if (selected.nextSibling) {
      select(selected.nextSibling);
      return;
    }
  }
  if (searchResults.firstChild) select(searchResults.firstChild);
}

function selectPreviousResult() {
  const selected = searchResults.querySelector(".selected");
  if (selected) {
    selected.classList.remove("selected");
    if (selected.previousSibling) {
      select(selected.previousSibling);
      return;
    }
  }
  if (searchResults.lastChild) select(searchResults.lastChild)
}

function scrollIntoViewIfNeeded(element) {
  const elementRect = element.getBoundingClientRect();
  const parentRect = element.parentNode.getBoundingClientRect();

  const isOutOfView = (
    elementRect.top < parentRect.top ||
    elementRect.left < parentRect.left ||
    elementRect.bottom > parentRect.bottom ||
    elementRect.right > parentRect.right
  );

  if (isOutOfView) {
    element.scrollIntoView({ block: 'center', inline: 'center' });
  }
}

function clickSelectedResult() {
  const selected = searchResults.querySelector(".selected") || searchResults.firstChild;
  if (!selected) return;
  selected.click();
}

document.addEventListener("keydown", event => {
  if (event.shiftKey || event.ctrlKey || event.altKey || event.metaKey) return;
  if (event.key === "/" && searchInput !== document.activeElement) {
    searchInput.focus();
    event.preventDefault();
  } else if (event.key === "Escape") {
    searchInput.blur();
    searchInput.value = "";
    onSearchInput();
    event.preventDefault();
  }
})

searchInput.addEventListener("focus", () => {
  searchHotkey.style.display = "none";
});
searchInput.addEventListener("blur", () => {
  if (searchInput.value === "") searchHotkey.style.display = "block";
});
searchInput.addEventListener("input", onSearchInput);
searchInput.addEventListener("keydown", event => {
  if (event.shiftKey || event.ctrlKey || event.altKey || event.metaKey) return;
  if (event.key === "ArrowDown") {
    selectNextResult();
    event.preventDefault();
  } else if (event.key === "ArrowUp") {
    selectPreviousResult();
    event.preventDefault();
  } else if (event.key === "Enter") {
    clickSelectedResult();
    event.preventDefault();
  }
});
searchClearButton.addEventListener("click", () => {
  searchInput.value = "";
  searchResults.replaceChildren();
  searchClearButton.style.display = "none";
  if (searchInput !== document.activeElement) searchHotkey.style.display = "block";
});

if (location.search) {
  const params = new URLSearchParams(location.search);
  const highlight = params.get("highlight");
  if (highlight) highlightText(decodeURIComponent(highlight));
}

function highlightText(term) {
  const escapedTerm = term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const regex = new RegExp(escapedTerm, 'gi');
  const content = document.querySelector('article>.content');
  traverseAndHighlight(content, regex);
}

function traverseAndHighlight(node, regex) {
  if (node.nodeType === Node.TEXT_NODE) {
    const match = node.nodeValue.match(regex);
    if (match) {
      const fragment = document.createDocumentFragment();

      let lastIndex = 0;
      node.nodeValue.replace(regex, (matchedText, offset) => {
        // Add plain text before the match
        if (offset > lastIndex) {
          fragment.appendChild(document.createTextNode(node.nodeValue.slice(lastIndex, offset)));
        }

        const span = document.createElement('span');
        span.className = 'highlight';
        span.textContent = matchedText;
        fragment.appendChild(span);

        lastIndex = offset + matchedText.length;
      });

      // Add any remaining text after the last match
      if (lastIndex < node.nodeValue.length) {
        fragment.appendChild(document.createTextNode(node.nodeValue.slice(lastIndex)));
      }

      node.parentNode.replaceChild(fragment, node);
    }
  } else if (node.nodeType === Node.ELEMENT_NODE) {
    node.childNodes.forEach(child => traverseAndHighlight(child, regex));
  }
}

function escapeHtml(unsafe) {
  return unsafe.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&#039;');
}