# This Python file uses the following encoding: utf-8
import sys
from PySide6.QtGui import QAction
from PySide6.QtWidgets import QApplication, QMainWindow, QWidget, QFileDialog, QStatusBar
from ui_form import Ui_Widget
from pathlib import Path

class Window(QMainWindow):
    """Main Window."""
    def __init__(self, parent=None):
        """Initializer."""
        super().__init__(parent)
        self.setWindowTitle("Frequent Finder")
        self.resize(400, 200)
        self.centralWidget = MainUI()
        self.setCentralWidget(self.centralWidget)

        # Setup status bar
        self.statusbar = self.statusBar()
        self.setStatusBar(self.statusbar)
        ## TODO: Delay showing "Ready" until after state file read and parsed
        self.statusbar.showMessage("Ready", 2000);

        self._createActions()
        self._createMenuBar()

    # Create menu bar
    def _createMenuBar(self):
        menuBar = self.menuBar()

        # Create menu items
        helpMenu = menuBar.addMenu("&Help")
        helpMenu.addAction(self.helpContentAction)

    def _createActions(self):
        # Help menu
        self.helpContentAction = QAction("&Help Content", self)
        self.helpContentAction.triggered.connect(self.helpContent)

    def helpContent(self):
        ## TODO: Logic for launching help goes here...
        print("Help selected")


class MainUI(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.ui = Ui_Widget()
        self.ui.setupUi(self)

        self._createActions()

    # Assign Actions to UI elements
    def _createActions(self):
        # Folder section
        self.ui.openFileDialogButton.clicked.connect(self._open_file_dialog)

        # fileExtension QLineEdit
        self.ui.fileExtension.editingFinished.connect(self.fileExtensionOnChange)


    def _open_file_dialog(self):
        dirname = QFileDialog.getExistingDirectory(
            self,
            "Select a Directory"
        )
        if dirname:
            path = Path(dirname)
            self.ui.workingFolderComboBox.addItem(str(path))
            debug("Folder selected: "+dirname)

        fileExt = self.ui.fileExtension.text()
        if ( fileExt ):
            ## TODO: Implement
            debug("There is a file extension: "+fileExt)
        else:
            win.statusbar.showMessage("Next: Add a file extension relevant to the current folder")


    def fileExtensionOnChange(self):
        ## Logic for when the file extension is changed
        currentFileExtension = self.ui.fileExtension.text()
        win.statusbar.showMessage("fileExtension changed to "+currentFileExtension)
        debug("fileExtension changed to "+currentFileExtension)

        ## TODONEXT: See and iterate ~/tmp13-scandir.py


def debug(msg):
    if debugState:
        print("Debug: "+msg);


if __name__ == "__main__":
    app = QApplication(sys.argv)

    debugState = 1; # Set to 0 or non-zero for extra information

    win = Window()
    win.show()
    sys.exit(app.exec())
