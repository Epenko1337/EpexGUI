using System.Collections;
using System.Collections.Generic;
using System.ComponentModel;
using System.Resources;
using System.Windows.Forms;

namespace WireSockUI.Extensions
{
    [ProvideProperty("ResourceKey", typeof(ToolStripItem))]
    internal class MenuTextExtender: Component, System.ComponentModel.IExtenderProvider, ISupportInitialize
    {
        private Dictionary<ToolStripItem, string> _items;

        public MenuTextExtender() : base() 
        {
            _items = new Dictionary<ToolStripItem, string>();
        }

        [Description("Full name of resource class, like YourAppNamespace.Resource1")]
        public string ResourceClassName { get; set; }

        public bool CanExtend(object extendee)
        {
            return (extendee is ToolStripItem);
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

        public void BeginInit() { }

        public void EndInit()
        {
            if (DesignMode)
                return;

            ResourceManager resourceManage = new ResourceManager(this.ResourceClassName, this.GetType().Assembly);

            foreach (KeyValuePair<ToolStripItem, string> menuItem in _items)
            {
                string value = resourceManage.GetString(menuItem.Value);
                menuItem.Key.Text = value;
            }
        }

        
    }
}
