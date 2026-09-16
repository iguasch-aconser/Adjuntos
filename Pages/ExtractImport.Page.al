pageextension 60811 ExtractImport extends "Posted Purchase Invoices"
{
    actions
    {
        addlast(processing)
        {
            action(DownloadAttachments)
            {
                ApplicationArea = All;
                Caption = 'Descargar adjuntos';
                ToolTip = 'Descarga todos los adjuntos de los documentos seleccionados en un ZIP.';
                Image = ExportFile;

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
                    ZipFileName: Text[50];
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

        addfirst(processing)
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

                trigger OnAction()
                begin
                    ImportAttachmentsFromZip();
                end;
            }
        }
    }

    local procedure ImportAttachmentsFromZip()
    var
        FileMgt: Codeunit "File Management";
        DataCompression: Codeunit "Data Compression";
        TempBlob: Codeunit "Temp Blob";
        EntryList: List of [Text];
        EntryListKey: Text;
        ZipFileName: Text;
        FileName: Text;
        TableID: Integer;
        No: Text;
        Nombre: Text;
        FileExtension: Text;
        InStream: InStream;
        EntryOutStream: OutStream;
        EntryInStream: InStream;
        Length: Integer;
        SelectZIPFileMsg: Label 'Selecciona el fichero ZIP';
        FileCount: Integer;
        PIH: Record "Purch. Inv. Header";
        DocAttach: Record "Document Attachment";
        NoPIHError: Label 'La factura de compra registrada %1 no existe.';
        ImportedMsg: Label '%1 adjuntos importados correctamente.';
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
            TempBlob.CreateOutStream(EntryOutStream);
            DataCompression.ExtractEntry(EntryListKey, EntryOutStream, Length);
            TempBlob.CreateInStream(EntryInStream);

            //Import each file where you want
            if not PIH.Get(No) then
                Error(NoPIHError, No);
            if not (TableID = Database::"Purch. Inv. Header") then
                Error('El adjunto %1 no pertenece a este tipo de tabla <>122', EntryListKey);

            //Elimina adjuntos anteriores a hoy
            DocAttach.Reset();
            DocAttach.SetRange("Table ID", Database::"Purch. Inv. Header");
            DocAttach.SetRange("No.", No);
            DocAttach.SetFilter(SystemCreatedAt, '<%1', CreateDateTime(Today, 000000T));
            if DocAttach.FindSet(true) then
                DocAttach.DeleteAll(false);

            //Adjunta fichero desde ZIP
            DocAttach.Init();
            DocAttach.Validate("Table ID", Database::"Purch. Inv. Header");
            DocAttach.Validate("No.", No);
            DocAttach.Validate("File Name", Nombre);
            DocAttach.Validate("File Extension", FileExtension);
            DocAttach."Document Reference ID".ImportStream(EntryInStream, FileName);
            DocAttach.Insert(false);
            FileCount += 1;
        end;

        //Close the zip file
        DataCompression.CloseZipArchive();

        if FileCount > 0 then
            Message(ImportedMsg, FileCount);
    end;

}