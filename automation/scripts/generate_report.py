#!/usr/bin/env python3
import warnings
warnings.filterwarnings("ignore", message=".*Remote manager daemon uses a newer GMP version.*")
import sys
import os
import smtplib
from datetime import datetime
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.application import MIMEApplication
from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer
from reportlab.lib import colors
from xml.etree import ElementTree
from gvm.connections import UnixSocketConnection
from gvm.protocols.gmp import Gmp
from gvm.transforms import EtreeCheckCommandTransform
from gvm.errors import GvmError

class BSORReportGenerator:
    def __init__(self):
        self.gmp_username = os.environ.get("GMP_USERNAME", "admin")
        self.gmp_password = os.environ.get("GMP_PASSWORD", "admin123")
        
    def get_report_xml(self, task_id):
        conn = UnixSocketConnection(path="/run/gvmd/gvmd.sock")
        transform = EtreeCheckCommandTransform()
        
        with Gmp(connection=conn, transform=transform) as gmp:
            # Dodaj timeout i ponowne próby
            try:
                gmp.authenticate(self.gmp_username, self.gmp_password)
            except GvmError as e:
                print(f"[auth] GMP Error: {e}")
                raise
            
            # Pobierz raporty dla zadania
            reports = gmp.get_reports(
                filter_string=f"task_id={task_id}",
                details=True,
                ignore_pagination=True
            )
            report_list = reports.xpath("report")

            if not report_list:
                raise Exception(f"No reports found for task {task_id}")
            
            # Pobierz pierwszy raport w formacie XML
            report_id = report_list[0].get("id")
            report = gmp.get_report(
                report_id=report_id,
                report_format_id="a994b278-1f62-11e1-96ac-406186ea4fc5"  # XML format ID
            )
            
            return report
    
    def parse_xml_report(self, xml_report):
        """Parsuj raport XML i wyciągnij kluczowe informacje"""
        results = []
        
        # Jeśli xml_report to string, parsuj go
        if isinstance(xml_report, str):
            root = ElementTree.fromstring(xml_report)
        else:
            root = xml_report
        
        # Podstawowe informacje o skanie
        scan_info = {
            'scan_time': datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            'total_hosts': len(root.findall(".//host")),
            'total_results': len(root.findall(".//result"))
        }
        
        # Wyniki vulnerabilities
        for result in root.findall(".//result"):
            host = result.findtext("host", "Unknown")
            name = result.findtext("name", "Unknown vulnerability")
            severity = float(result.findtext("severity", "0"))
            description = result.findtext("description", "No description")
            
            # Określ poziom zagrożenia
            if severity >= 7.0:
                threat_level = "High"
            elif severity >= 4.0:
                threat_level = "Medium"
            elif severity > 0:
                threat_level = "Low"
            else:
                threat_level = "Info"
            
            results.append({
                'host': host,
                'name': name,
                'severity': severity,
                'threat_level': threat_level,
                'description': description
            })
        
        # Sortuj według severity (najwyższej najpierw)
        results.sort(key=lambda x: x['severity'], reverse=True)
        
        return scan_info, results
    
    def generate_pdf(self, scan_info, results, output_path):
        """Generuj profesjonalny raport PDF w formie listy"""
        doc = SimpleDocTemplate(output_path, pagesize=A4, 
                        leftMargin=40, rightMargin=40, 
                        topMargin=40, bottomMargin=40)
        story = []
        styles = getSampleStyleSheet()
        available_width = A4[0] - 80

        # Stwórz specjalne style dla listy
        vuln_title_style = styles['Normal'].clone('VulnTitleStyle')
        vuln_title_style.fontSize = 10
        vuln_title_style.fontName = 'Helvetica-Bold'
        vuln_title_style.spaceAfter = 6
        vuln_title_style.leftIndent = 20
        
        vuln_detail_style = styles['Normal'].clone('VulnDetailStyle')
        vuln_detail_style.fontSize = 9
        vuln_detail_style.leftIndent = 30
        vuln_detail_style.spaceAfter = 4
        
        vuln_desc_style = styles['Normal'].clone('VulnDescStyle')
        vuln_desc_style.fontSize = 8
        vuln_desc_style.leftIndent = 30
        vuln_desc_style.spaceAfter = 12
        vuln_desc_style.textColor = colors.darkgrey

        # Tytuł
        title = Paragraph("BSO Security Scan Report", styles['Title'])
        story.append(title)
        story.append(Spacer(1, 12))
        
        # Informacje o skanie
        scan_summary = f"""
        <b>Scan Summary</b><br/>
        Scan Date: {scan_info['scan_time']}<br/>
        Total Hosts Scanned: {scan_info['total_hosts']}<br/>
        Total Vulnerabilities Found: {scan_info['total_results']}<br/>
        """
        story.append(Paragraph(scan_summary, styles['Normal']))
        story.append(Spacer(1, 20))
        
        # Statystyki zagrożeń
        threat_stats = {'High': 0, 'Medium': 0, 'Low': 0, 'Info': 0}
        for result in results:
            threat_stats[result['threat_level']] += 1
        
        stats_text = f"""
        <b>Threat Level Distribution</b><br/>
        High: {threat_stats['High']} | Medium: {threat_stats['Medium']} | 
        Low: {threat_stats['Low']} | Info: {threat_stats['Info']}
        """
        story.append(Paragraph(stats_text, styles['Normal']))
        story.append(Spacer(1, 20))
        
        # LISTA PODATNOŚCI - zamiast tabeli
        if results:
            story.append(Paragraph("<b>Detailed Vulnerability Results</b>", styles['Heading2']))
            story.append(Spacer(1, 12))
            
            # Sortuj według threat_level (High -> Medium -> Low -> Info) i severity
            threat_order = {'High': 4, 'Medium': 3, 'Low': 2, 'Info': 1}
            sorted_results = sorted(results, 
                                key=lambda x: (threat_order[x['threat_level']], x['severity']), 
                                reverse=True)
            
            # Wyświetl wszystkie wyniki (nie ograniczaj do 15)
            for i, result in enumerate(sorted_results, 1):
                # Określ kolor dla poziomu zagrożenia
                if result['threat_level'] == 'High':
                    level_color = 'red'
                elif result['threat_level'] == 'Medium':
                    level_color = 'orange'
                elif result['threat_level'] == 'Low':
                    level_color = 'goldenrod'
                else:
                    level_color = 'blue'
                
                # Tytuł podatności z numerem
                vuln_title = f"""
                <b>{i}. {result['name']}</b>
                """
                story.append(Paragraph(vuln_title, vuln_title_style))
                
                # Szczegóły podatności
                details = f"""
                <b>Host:</b> {result['host']} | 
                <b>Severity:</b> {result['severity']:.1f} | 
                <b>Threat Level:</b> <font color="{level_color}"><b>{result['threat_level']}</b></font>
                """
                story.append(Paragraph(details, vuln_detail_style))
                
                # Pełny opis (bez ucięcia)
                description = f"""
                <b>description:</b><br/>
                {result['description']}
                """
                story.append(Paragraph(description, vuln_desc_style))
                
                # Dodaj linię oddzielającą (oprócz ostatniego elementu)
                if i < len(sorted_results):
                    story.append(Spacer(1, 6))
                    # Dodaj subtelną linię oddzielającą
                    from reportlab.platypus import HRFlowable
                    story.append(HRFlowable(width="100%", thickness=0.5, color=colors.lightgrey))
                    story.append(Spacer(1, 6))
        
        # Generuj PDF
        doc.build(story)
        print(f"[report] PDF generated: {output_path}")

    def send_email(self, pdf_path, task_id):
        """Wyślij raport PDF mailem"""
        smtp_server = os.environ.get("SMTP_SERVER", "smtp.gmail.com")
        smtp_port = int(os.environ.get("SMTP_PORT", "587"))
        smtp_user = os.environ.get("SMTP_USER")
        smtp_password = os.environ.get("SMTP_PASSWORD")
        report_email = os.environ.get("REPORT_EMAIL")
        
        if not all([smtp_user, smtp_password, report_email]):
            print("[email] Missing email configuration, skipping email send")
            return
        
        # Stwórz wiadomość
        msg = MIMEMultipart()
        msg['From'] = smtp_user
        msg['To'] = report_email
        msg['Subject'] = f"BSO Security Scan Report - {datetime.now().strftime('%Y-%m-%d')}"
        
        # Treść wiadomości
        body = f"""
BSO Automated Security Scan Report

Task ID: {task_id}
Scan completed: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

Please find the detailed security report attached as PDF.

Best regards,
BSO Security Scanner
        """
        
        msg.attach(MIMEText(body, 'plain'))
        
        # Załącz PDF
        with open(pdf_path, "rb") as attachment:
            pdf_part = MIMEApplication(attachment.read(), _subtype="pdf")
            pdf_part.add_header(
                'Content-Disposition',
                f'attachment; filename="BSO_Security_Report_{task_id[:8]}.pdf"'
            )
            msg.attach(pdf_part)
        
        # Wyślij email
        try:
            with smtplib.SMTP(smtp_server, smtp_port) as server:
                server.starttls()
                server.login(smtp_user, smtp_password)
                server.send_message(msg)
                print(f"[email] Report sent successfully to {report_email}")
        except Exception as e:
            print(f"[email] Failed to send email: {e}")

def main():
    if len(sys.argv) != 2:
        print("Usage: generate_report.py <task_id>")
        sys.exit(1)
    
    task_id = sys.argv[1]
    generator = BSORReportGenerator()
    
    try:
        # 1. Pobierz raport XML z Greenbone
        print(f"[report] Fetching report for task: {task_id}")
        xml_report = generator.get_report_xml(task_id)
        
        # 2. Parsuj XML
        print("[report] Parsing report data...")
        scan_info, results = generator.parse_xml_report(xml_report)
        
        # 3. Generuj PDF
        pdf_path = f"/tmp/BSO_Report_{task_id[:8]}_{datetime.now().strftime('%Y%m%d_%H%M')}.pdf"
        print("[report] Generating PDF report...")
        generator.generate_pdf(scan_info, results, pdf_path)
        
        # 4. Wyślij mailem
        print("[report] Sending email...")
        generator.send_email(pdf_path, task_id)
        
        print("[report] Report generation and delivery completed!")
        
    except Exception as e:
        print(f"[report] Error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
