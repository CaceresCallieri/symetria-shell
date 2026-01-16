pragma Singleton

import qs.config
import qs.services
import qs.utils
import Quickshell

// Clipboard search service extending Searcher
// Note: Provides search() instead of overriding query() because it includes
// maxDisplayed limiting which is clipboard-specific behavior
Searcher {
    list: Clipboard.entries
    key: "preview"
    useFuzzy: Config.clipboard.useFuzzy

    function search(searchText: string): list<var> {
        const maxResults = Config.clipboard.maxDisplayed;

        if (!searchText)
            return list.slice(0, maxResults);

        return query(searchText).slice(0, maxResults);
    }
}
