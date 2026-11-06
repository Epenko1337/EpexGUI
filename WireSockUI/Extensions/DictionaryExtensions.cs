using System.Collections.Generic;

namespace WireSockUI.Extensions
{
    public static class DictionaryExtensions
    {
        public static TVal Get<TKey, TVal>(this Dictionary<TKey, TVal> dictionary, TKey key, TVal defaultVal = default)
        {
            return dictionary.TryGetValue(key, out var val) ? val : defaultVal;
        }
    }
}