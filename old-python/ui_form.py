# -*- coding: utf-8 -*-

################################################################################
## Form generated from reading UI file 'form.ui'
##
## Created by: Qt User Interface Compiler version 6.7.2
##
## WARNING! All changes made in this file will be lost when recompiling UI file!
################################################################################

from PySide6.QtCore import (QCoreApplication, QDate, QDateTime, QLocale,
    QMetaObject, QObject, QPoint, QRect,
    QSize, QTime, QUrl, Qt)
from PySide6.QtGui import (QBrush, QColor, QConicalGradient, QCursor,
    QFont, QFontDatabase, QGradient, QIcon,
    QImage, QKeySequence, QLinearGradient, QPainter,
    QPalette, QPixmap, QRadialGradient, QTransform)
from PySide6.QtWidgets import (QApplication, QComboBox, QGridLayout, QHBoxLayout,
    QLabel, QLayout, QLineEdit, QListWidget,
    QListWidgetItem, QPushButton, QSizePolicy, QSpacerItem,
    QVBoxLayout, QWidget)

class Ui_Widget(object):
    def setupUi(self, Widget):
        if not Widget.objectName():
            Widget.setObjectName(u"Widget")
        Widget.resize(550, 400)
        sizePolicy = QSizePolicy(QSizePolicy.Policy.Fixed, QSizePolicy.Policy.Fixed)
        sizePolicy.setHorizontalStretch(0)
        sizePolicy.setVerticalStretch(0)
        sizePolicy.setHeightForWidth(Widget.sizePolicy().hasHeightForWidth())
        Widget.setSizePolicy(sizePolicy)
        Widget.setMinimumSize(QSize(550, 300))
        Widget.setAutoFillBackground(False)
        self.verticalLayout = QVBoxLayout(Widget)
        self.verticalLayout.setObjectName(u"verticalLayout")
        self.gridLayout_2 = QGridLayout()
        self.gridLayout_2.setObjectName(u"gridLayout_2")
        self.label = QLabel(Widget)
        self.label.setObjectName(u"label")

        self.gridLayout_2.addWidget(self.label, 0, 0, 1, 1)

        self.workingFolderComboBox = QComboBox(Widget)
        self.workingFolderComboBox.setObjectName(u"workingFolderComboBox")
        self.workingFolderComboBox.setMinimumSize(QSize(300, 0))
        self.workingFolderComboBox.setInsertPolicy(QComboBox.InsertPolicy.InsertAtTop)

        self.gridLayout_2.addWidget(self.workingFolderComboBox, 0, 1, 1, 2)

        self.openFileDialogButton = QPushButton(Widget)
        self.openFileDialogButton.setObjectName(u"openFileDialogButton")
        icon = QIcon(QIcon.fromTheme(QIcon.ThemeIcon.FolderNew))
        self.openFileDialogButton.setIcon(icon)

        self.gridLayout_2.addWidget(self.openFileDialogButton, 0, 3, 1, 1)

        self.label_2 = QLabel(Widget)
        self.label_2.setObjectName(u"label_2")

        self.gridLayout_2.addWidget(self.label_2, 1, 0, 1, 1)

        self.fileExtension = QLineEdit(Widget)
        self.fileExtension.setObjectName(u"fileExtension")

        self.gridLayout_2.addWidget(self.fileExtension, 1, 1, 1, 1)

        self.horizontalSpacer_2 = QSpacerItem(40, 20, QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Minimum)

        self.gridLayout_2.addItem(self.horizontalSpacer_2, 1, 2, 1, 1)


        self.verticalLayout.addLayout(self.gridLayout_2)

        self.ProjectsOrFilesFoundLabel = QLabel(Widget)
        self.ProjectsOrFilesFoundLabel.setObjectName(u"ProjectsOrFilesFoundLabel")
        sizePolicy1 = QSizePolicy(QSizePolicy.Policy.Preferred, QSizePolicy.Policy.MinimumExpanding)
        sizePolicy1.setHorizontalStretch(0)
        sizePolicy1.setVerticalStretch(0)
        sizePolicy1.setHeightForWidth(self.ProjectsOrFilesFoundLabel.sizePolicy().hasHeightForWidth())
        self.ProjectsOrFilesFoundLabel.setSizePolicy(sizePolicy1)

        self.verticalLayout.addWidget(self.ProjectsOrFilesFoundLabel)

        self.horizontalLayout_4 = QHBoxLayout()
        self.horizontalLayout_4.setObjectName(u"horizontalLayout_4")
        self.listWidget = QListWidget(Widget)
        self.listWidget.setObjectName(u"listWidget")

        self.horizontalLayout_4.addWidget(self.listWidget)

        self.horizontalSpacer_3 = QSpacerItem(40, 20, QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Minimum)

        self.horizontalLayout_4.addItem(self.horizontalSpacer_3)

        self.horizontalLayout_4.setStretch(0, 8)

        self.verticalLayout.addLayout(self.horizontalLayout_4)

        self.horizontalLayout = QHBoxLayout()
#ifndef Q_OS_MAC
        self.horizontalLayout.setSpacing(-1)
#endif
        self.horizontalLayout.setObjectName(u"horizontalLayout")
        self.horizontalLayout.setSizeConstraint(QLayout.SizeConstraint.SetDefaultConstraint)
        self.horizontalLayout.setContentsMargins(0, 5, 0, 5)
        self.pushButton_2 = QPushButton(Widget)
        self.pushButton_2.setObjectName(u"pushButton_2")
        self.pushButton_2.setEnabled(False)
        sizePolicy2 = QSizePolicy(QSizePolicy.Policy.Maximum, QSizePolicy.Policy.Fixed)
        sizePolicy2.setHorizontalStretch(0)
        sizePolicy2.setVerticalStretch(0)
        sizePolicy2.setHeightForWidth(self.pushButton_2.sizePolicy().hasHeightForWidth())
        self.pushButton_2.setSizePolicy(sizePolicy2)
        self.pushButton_2.setMinimumSize(QSize(100, 32))
        self.pushButton_2.setAutoFillBackground(False)

        self.horizontalLayout.addWidget(self.pushButton_2)

        self.pushButton = QPushButton(Widget)
        self.pushButton.setObjectName(u"pushButton")
        self.pushButton.setEnabled(False)
        sizePolicy2.setHeightForWidth(self.pushButton.sizePolicy().hasHeightForWidth())
        self.pushButton.setSizePolicy(sizePolicy2)
        self.pushButton.setMinimumSize(QSize(100, 32))
        self.pushButton.setAutoFillBackground(False)

        self.horizontalLayout.addWidget(self.pushButton)

        self.horizontalSpacer = QSpacerItem(40, 20, QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Minimum)

        self.horizontalLayout.addItem(self.horizontalSpacer)

        self.pushButton_3 = QPushButton(Widget)
        self.pushButton_3.setObjectName(u"pushButton_3")
        self.pushButton_3.setEnabled(False)
        sizePolicy2.setHeightForWidth(self.pushButton_3.sizePolicy().hasHeightForWidth())
        self.pushButton_3.setSizePolicy(sizePolicy2)
        self.pushButton_3.setMinimumSize(QSize(100, 32))
        self.pushButton_3.setAutoFillBackground(False)

        self.horizontalLayout.addWidget(self.pushButton_3)

        self.horizontalLayout.setStretch(2, 8)

        self.verticalLayout.addLayout(self.horizontalLayout)


        self.retranslateUi(Widget)

        QMetaObject.connectSlotsByName(Widget)
    # setupUi

    def retranslateUi(self, Widget):
        Widget.setWindowTitle(QCoreApplication.translate("Widget", u"FrequentFinder", None))
        self.label.setText(QCoreApplication.translate("Widget", u"Working Folder", None))
#if QT_CONFIG(tooltip)
        self.workingFolderComboBox.setToolTip(QCoreApplication.translate("Widget", u"Shows frequently used folders", None))
#endif // QT_CONFIG(tooltip)
#if QT_CONFIG(tooltip)
        self.openFileDialogButton.setToolTip(QCoreApplication.translate("Widget", u"Choose a folder", None))
#endif // QT_CONFIG(tooltip)
        self.openFileDialogButton.setText("")
        self.label_2.setText(QCoreApplication.translate("Widget", u"File Extension", None))
#if QT_CONFIG(tooltip)
        self.fileExtension.setToolTip(QCoreApplication.translate("Widget", u"Enter a file extension for files you care about in the selected folder", None))
#endif // QT_CONFIG(tooltip)
        self.ProjectsOrFilesFoundLabel.setText(QCoreApplication.translate("Widget", u"Projects found:", None))
        self.pushButton_2.setText(QCoreApplication.translate("Widget", u"Save Config", None))
        self.pushButton.setText(QCoreApplication.translate("Widget", u"Set default file", None))
        self.pushButton_3.setText(QCoreApplication.translate("Widget", u"Open files", None))
    # retranslateUi

