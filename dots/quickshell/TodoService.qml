pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Lista de tarefas da Agenda do Hub. Estado do usuário:
// ~/.config/quickshell/todo.json ([{ text, done }]).
Singleton {
    id: root

    property var items: []
    property bool ready: false
    readonly property int openCount: items.filter(i => !i.done).length

    FileView {
        id: file
        path: Quickshell.env("HOME") + "/.config/quickshell/todo.json"
        printErrors: false
        onLoaded: {
            try {
                const d = JSON.parse(text());
                root.items = Array.isArray(d) ? d.filter(i => i && typeof i.text === "string") : [];
            } catch (e) { root.items = []; }
            root.ready = true;
        }
        onLoadFailed: root.ready = true
    }

    // Só grava depois de ler: antes, uma tarefa nova com a lista ainda vazia
    // em memória apagaria as salvas.
    function save(list) {
        root.items = list;
        if (root.ready) file.setText(JSON.stringify(list, null, 1) + "\n");
    }
    function add(text) {
        const t = (text || "").trim();
        if (t !== "" && root.ready) save(root.items.concat([{ text: t, done: false }]));
    }
    function toggle(i) {
        const l = root.items.slice();
        if (!l[i]) return;
        l[i] = { text: l[i].text, done: !l[i].done };
        save(l);
    }
    function remove(i) {
        const l = root.items.slice();
        l.splice(i, 1);
        save(l);
    }
    function clearDone() { save(root.items.filter(i => !i.done)); }
}
