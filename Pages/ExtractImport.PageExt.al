namespace DefaultPublisher.ADJ;
using Microsoft.Foundation.Attachment;
using Microsoft.Purchases.History;
using System.IO;
using System.Security.AccessControl;
using System.Utilities;

pageextension 60811 ExtractImport extends "Posted Purchase Invoices"
{
    actions
    {
        addfirst(processing)
        {
            action(DownloadAttachments)
            {
                ApplicationArea = All;
                Caption = 'Descargar adjuntos';
                ToolTip = 'Descarga todos los adjuntos de los documentos seleccionados en un ZIP.';
                Image = ExportFile;
                Visible = IsAuthorized;

                trigger OnAction()
                var
                    MyRecord: Record "Purch. Inv. Header";
                    DocumentAttachment: Record "Document Attachment";
                    DataCompression: Codeunit "Data Compression";
                    TempBlob: Codeunit "Temp Blob";
                    DocumentOutStream: OutStream;
                    DocumentInStream: InStream;
                    ZipOutStream: OutStream;
                    ZipInStream: InStream;
                    FullFileName: Text;
                    ZipFileName: Text;
                begin
                    MyRecord.Reset();
                    CurrPage.SetSelectionFilter(MyRecord);
                    if MyRecord.FindSet(false) then begin
                        ZipFileName := Format(Database::"Purch. Inv. Header") + '.zip';
                        DataCompression.CreateZipArchive();
                        repeat
                            DocumentAttachment.Reset();
                            DocumentAttachment.SetRange("Table ID", Database::"Purch. Inv. Header");
                            DocumentAttachment.SetFilter("No.", MyRecord."No.");
                            if DocumentAttachment.FindSet(false) then
                                repeat
                                    if DocumentAttachment."Document Reference ID".HasValue then begin
                                        Clear(TempBlob);
                                        TempBlob.CreateOutStream(DocumentOutStream);
                                        DocumentAttachment."Document Reference ID".ExportStream(DocumentOutStream);
                                        TempBlob.CreateInStream(DocumentInStream);
                                        FullFileName := Format(Database::"Purch. Inv. Header") + '-' + Format(MyRecord."No.") + '-' + DocumentAttachment."File Name" + '.' + DocumentAttachment."File Extension";
                                        DataCompression.AddEntry(DocumentInStream, FullFileName);
                                    end;
                                until DocumentAttachment.Next() = 0;
                        until MyRecord.Next() = 0;
                        Clear(TempBlob);
                        TempBlob.CreateOutStream(ZipOutStream);
                        DataCompression.SaveZipArchive(ZipOutStream);
                        TempBlob.CreateInStream(ZipInStream);
                        DownloadFromStream(ZipInStream, '', '', '', ZipFileName);
                    end;
                end;
            }
        }

        addlast(processing)
        {
            action(ImportZipFile)
            {
                Caption = 'Importar fichero Zip con adjuntos';
                ApplicationArea = All;
                Promoted = true;
                PromotedCategory = Process;
                PromotedIsBig = true;
                Image = Import;
                ToolTip = 'Importar adjuntos desde fichero Zip';
                Visible = IsAuthorized;

                trigger OnAction()
                begin
                    ImportAttachmentsFromZip();
                end;
            }
        }
    }

    var
        IsAuthorized: Boolean;

    trigger OnOpenPage()
    var
        User: Record User;
    begin
        if User.Get(UserSecurityId()) then
            IsAuthorized := (User."User Name" = 'IGUASCH')
        else
            IsAuthorized := false;
    end;

    local procedure ImportAttachmentsFromZip()
    var
        DocAttach: Record "Document Attachment";
        PIH: Record "Purch. Inv. Header";
        FileMgt: Codeunit "File Management";
        DataCompression: Codeunit "Data Compression";
        TempBlob: Codeunit "Temp Blob";
        RecRef: RecordRef;
        EntryList: List of [Text];
        EntryListKey: Text;
        ZipFileName: Text;
        FileName: Text;
        TableID: Integer;
        No: Text[20];
        Nombre: Text[250];
        FileExtension: Text[30];
        InStream: InStream;
        EntryOutStream: OutStream;
        EntryInStream: InStream;
        SelectZIPFileMsg: Label 'Selecciona el fichero ZIP';
        FileCount: Integer;
        NoPIHErrorLbl: Label 'La factura de compra registrada %1 no existe.', Comment = '%1 = Factura de compra registrada';
        ImportedMsgLbl: Label '%1 adjuntos importados correctamente.', Comment = '%1 = Número de adjuntos importados';

    begin
        //Upload zip file
        if not UploadIntoStream(SelectZIPFileMsg, '', 'Zip Files|*.zip', ZipFileName, InStream) then
            Error('');

        //Extract zip file and store files to list type
        DataCompression.OpenZipArchive(InStream, false);
        DataCompression.GetEntryList(EntryList);

        FileCount := 0;

        //Loop files from the list type
        foreach EntryListKey in EntryList do begin
            FileName := CopyStr(FileMgt.GetFileNameWithoutExtension(EntryListKey), 1, MaxStrLen(FileName));
            Nombre := CopyStr(FileName.Split('-').Get(3), 1, MaxStrLen(Nombre));
            FileExtension := CopyStr(FileMgt.GetExtension(EntryListKey), 1, MaxStrLen(FileExtension));
            No := CopyStr(FileName.Split('-').Get(2), 1, MaxStrLen(No));
            Evaluate(TableID, CopyStr(FileName.Split('-').Get(1), 1, MaxStrLen(FileName)));
            Clear(TempBlob);
            TempBlob.CreateOutStream(EntryOutStream);
            DataCompression.ExtractEntry(EntryListKey, EntryOutStream);
            TempBlob.CreateInStream(EntryInStream);

            //Import each file where you want
            if not PIH.Get(No) then
                Error(NoPIHErrorLbl, No);
            if not (TableID = Database::"Purch. Inv. Header") then
                Error('El adjunto %1 no pertenece a este tipo de tabla <>122', EntryListKey);

            //Adjunta fichero desde ZIP
            DocAttach.Init();
            DocAttach.Validate("File Name", Nombre);
            DocAttach.Validate("File Extension", FileExtension);
            DocAttach."Document Reference ID".ImportStream(EntryInStream, FileName);
            if DocAttach."Document Reference ID".HasValue then begin
                RecRef.GetTable(PIH);
                DocAttach.InitFieldsFromRecRef(RecRef);
                if Insertar(DocAttach) then
                    FileCount += 1
                else
                    Message('Ha fallado el fichero %1 del documento %2', Nombre, No);
            end;
        end;

        //Close the zip file
        DataCompression.CloseZipArchive();

        if FileCount > 0 then
            Message(ImportedMsgLbl, FileCount);
    end;

    [TryFunction]
    local procedure Insertar(DocAttach: Record "Document Attachment")
    var
        RepDocAttach: Record "Document Attachment";
    begin
        RepDocAttach.Reset();
        RepDocAttach.SetRange("Table ID", DocAttach."Table ID");
        RepDocAttach.SetRange("No.", DocAttach."No.");
        RepDocAttach.SetRange("Document Type", DocAttach."Document Type");
        RepDocAttach.SetRange("File Name", DocAttach."File Name");
        RepDocAttach.SetRange("File Extension", DocAttach."File Extension");
        RepDocAttach.SetRange("File Type", DocAttach."File Type");
        RepDocAttach.SetRange("Line No.", DocAttach."Line No.");
        if RepDocAttach.FindSet(true) then
            RepDocAttach.DeleteAll(true);
        DocAttach.Insert(true);
    end;
}