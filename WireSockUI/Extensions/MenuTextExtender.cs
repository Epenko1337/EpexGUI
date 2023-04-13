using System.Collections.Generic;
using System.ComponentModel;
using System.Resources;
using System.Windows.Forms;

namespace WireSockUI.Extensions
{
    [ProvideProperty("ResourceKey", typeof(ToolStripItem))]
    internal class MenuTextExtender : Component, IExtenderProvider, ISupportInitialize
    {
        private readonly Dictionary<ToolStripItem, string> _items;

        public MenuTextExtender()
        {
            _items = new Dictionary<ToolStripItem, string>();
        }

        [Description("Full name of resource class, like YourAppNamespace.Resource1")]
        public string ResourceClassName { get; set; }

        public bool CanExtend(object extendee)
        {
            return extendee is ToolStripItem;
        }

        public void BeginInit()
        {
        }

        public void EndInit()
        {
            if (DesignMode)
                return;

            var resourceManage = new ResourceManager(ResourceClassName, GetType().Assembly);

            foreach (var menuItem in _items)
            {
                var value = resourceManage.GetString(menuItem.Value);
                menuItem.Key.Text = value;
            }
        }

        public string GetResourceKey(ToolStripItem item)
        {
            string value;

            if (_items.TryGetValue(item, out value))
                return value;

            return null;
        }

        public void SetResourceKey(ToolStripItem item, string key)
        {
            if (string.IsNullOrEmpty(key))
                _items.Remove(item);
            else
                _items[item] = key;
        }
    }
}