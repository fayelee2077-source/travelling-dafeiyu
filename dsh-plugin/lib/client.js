/**
 * Browser half of dsh-living-dock: the little home of 《旅行的大肥鱼》 as a page inside DSH.
 *
 * Written against the DSH client module contract (`window.__ModuleLoader__`), like other plugins' pages, so
 * no bundler is needed: `react` comes from the shell; `apply(ctx)` registers a sidebar entry
 * (`sidebar.panellist`) and the page it opens (the layout's keyed `main` slot, same id). The page is an iframe
 * of the little home's web version, which the plugin serves under /living-dock/ of DSH's own web server
 * (lib/web.js). The record lives in the plugin, so the layout unmounting the page (opening a chat) loses
 * nothing; coming back loads the little home again.
 */

window.__ModuleLoader__.load({
  id: 'dsh-living-dock',
  factory: (require) => {
    var module = { exports: {} };
    var exports = module.exports;
    Object.defineProperty(exports, Symbol.toStringTag, { value: 'Module' });

    const React = require('react');
    const h = React.createElement;

    /** Must match lib/web.js DSH_BASE. */
    const BASE = '/living-dock';
    const PANEL_ID = 'living-dock';
    const NS = 'living-dock';
    const DICTIONARY = {
      zh: {
        panel: '旅行的大肥鱼',
        frameTitle: '《旅行的大肥鱼》小家',
        unreachableTitle: '小家没有打开',
        unreachableBody: '插件没有回应。请确认 dsh-living-dock 已经在这个配置里启用，然后重启 DSH。',
        noPageTitle: '这个插件里没有小家网页',
        noPageBody: '插件文件夹里缺少 web 文件夹（小家网页版）。可以重新运行「安装插件.bat」，或者打开《旅行的大肥鱼》窗口版。',
      },
      en: {
        panel: 'Travelling Big Fish',
        frameTitle: 'The little home',
        unreachableTitle: 'The little home is not reachable',
        unreachableBody: 'The plugin did not answer. Check that dsh-living-dock is enabled in this profile, then restart DSH.',
        noPageTitle: 'No little home page in this plugin',
        noPageBody: 'The plugin folder has no web folder (the web version). Run the installer again, or open the window version.',
      },
    };
    let t = (key) => DICTIONARY.en[key] ?? key;
    const inject = ['slots', 'locale'];

    function origin() {
      return window.location?.origin && window.location.origin !== 'null' ? window.location.origin : '';
    }

    function Message({ title, body }) {
      return h('div', {
        style: { padding: '28px', font: '13px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", sans-serif', opacity: 0.75 },
      }, h('div', { style: { fontWeight: 650, marginBottom: 6 } }, title), h('div', null, body));
    }

    function HomePanel() {
      const [status, setStatus] = React.useState('loading');
      React.useEffect(() => {
        let cancelled = false;
        fetch(`${BASE}/health`)
          .then((r) => (r.ok ? r.json() : Promise.reject(new Error(String(r.status)))))
          .then((v) => { if (!cancelled) setStatus(v.page ? 'ready' : 'nopage'); })
          .catch(() => { if (!cancelled) setStatus('error'); });
        return () => { cancelled = true; };
      }, []);
      if (status === 'error') return h(Message, { title: t('unreachableTitle'), body: t('unreachableBody') });
      if (status === 'nopage') return h(Message, { title: t('noPageTitle'), body: t('noPageBody') });
      if (status === 'loading') return null;
      return h('iframe', {
        src: `${origin()}${BASE}/`,
        title: t('frameTitle'),
        allow: 'autoplay',
        style: { width: '100%', height: '100%', minHeight: '520px', border: 0, display: 'block', background: '#1d1a24' },
      });
    }

    /** A little house with a heart on the door (the sidebar icon, drawn in the shell's own colour). */
    function HomeIcon() {
      return h('svg', {
        width: 16, height: 16, viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor', strokeWidth: 1.7,
        strokeLinecap: 'round', strokeLinejoin: 'round', 'aria-hidden': true, focusable: false,
      },
      h('path', { d: 'M3 11.5 12 4l9 7.5' }),
      h('path', { d: 'M5.5 9.5V20h13V9.5' }),
      h('path', { d: 'M12 17.2s-2.6-1.6-2.6-3.3a1.4 1.4 0 0 1 2.6-.7 1.4 1.4 0 0 1 2.6.7c0 1.7-2.6 3.3-2.6 3.3z' }));
    }

    function registerUi(ctx) {
      ctx.slots.inject('main', () => ctx.slots.register({ name: 'main', key: PANEL_ID, locale: NS }, HomePanel));
      ctx.slots.inject('sidebar.panellist', () =>
        ctx.slots.register({ name: 'sidebar.panellist', id: PANEL_ID, order: 30, locale: NS, label: () => t('panel') }, HomeIcon));
    }

    async function apply(ctx) {
      const disposeLocale = ctx.locale.register(NS, DICTIONARY);
      t = ctx.locale.bind(NS);
      const ui = ctx.inject(['slots'], () => registerUi(ctx));
      return () => {
        ui?.dispose?.();
        disposeLocale?.();
      };
    }

    exports.PANEL_ID = PANEL_ID;
    exports.apply = apply;
    exports.inject = inject;
    return module.exports;
  },
});
