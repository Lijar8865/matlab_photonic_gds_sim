# -*- coding: utf-8 -*-
# ----------------------------------------------
# Script Recorded by Ansys Electronics Desktop Version 2025.1.0
import ScriptEnv
import os
import json
# define function
################################################################################################################


def create_sweep_polyline(oEditor, points, Str_name, Material, SweepVector):
    # 在HFSS中创建多段线并拉伸，赋予材料属性。
    #     参数:
    #         oEditor: HFSS的3D Modeler编辑器对象
    #         points: [(x, y), ...]，点坐标列表
    #         Str_name: 生成结构的名称
    #         Material: 材料名称字符串
    #         SweepVector: (x, y, z)，拉伸向量，单位字符串，如("0um", "0um", "-4um")
    polyline_points = []
    for x, y in points:
        point = [
            "NAME:PLPoint",
            "X:=", "{}nm".format(x),
            "Y:=", "{}nm".format(y),
            "Z:=", "2um"
        ]
        polyline_points.append(point)

    segments = []
    for i in range(len(points)-1):
        segment = [
            "NAME:PLSegment",
            "SegmentType:=", "Line",
            "StartIndex:=", i,
            "NoOfPoints:=", 2
        ]
        segments.append(segment)

    oEditor.CreatePolyline(
        [
            "NAME:PolylineParameters",
            "IsPolylineCovered:=", True,
            "IsPolylineClosed:=", True,
            [
                "NAME:PolylinePoints"
            ] + polyline_points,
            [
                "NAME:PolylineSegments"
            ] + segments,
            [
                "NAME:PolylineXSection",
                "XSectionType:=", "None",
                "XSectionOrient:=", "Auto",
                "XSectionWidth:=", "0nm",
                "XSectionTopWidth:=", "0nm",
                "XSectionHeight:=", "0nm",
                "XSectionNumSegments:=", "0",
                "XSectionBendType:=", "Corner"
            ]
        ],
        [
            "NAME:Attributes",
            "Name:=", Str_name,
            "Flags:=", "",
            "Color:=", "(255 215 0)",
            "Transparency:=", 0,
            "PartCoordinateSystem:=", "Global",
            "MaterialValue:=", "\"vacuum\"",
            "SurfaceMaterialValue:=", "\"\"",
            "SolveInside:=", True,
            "ShellElement:=", False
        ])

    oEditor.SweepAlongVector(
        [
            "NAME:Selections",
            "Selections:=", Str_name,
            "NewPartsModelFlag:=", "Model"
        ],
        [
            "NAME:VectorSweepParameters",
            "DraftAngle:=", "0deg",
            "DraftType:=", "Round",
            "CheckFaceFaceIntersection:=", False,
            "ClearAllIDs:=", False,
            "SweepVectorX:=", SweepVector[0],
            "SweepVectorY:=", SweepVector[1],
            "SweepVectorZ:=", SweepVector[2]
        ])
    oEditor.AssignMaterial(
        [
            "NAME:Selections",
            "AllowRegionDependentPartSelectionForPMLCreation:=", True,
            "AllowRegionSelectionForPMLCreation:=", True,
            "Selections:=", Str_name
        ],
        [
            "NAME:Attributes",
            "MaterialValue:=", "\"{}\"".format(Material),
            "SolveInside:=", True,
            "ShellElement:=", False,
            "ShellElementThickness:=", "nan ",
            "ReferenceTemperature:=", "nan ",
            "IsMaterialEditable:=", True,
            "IsSurfaceMaterialEditable:=", True,
            "UseMaterialAppearance:=", False,
            "IsLightweight:=", False
        ])


def change_local_variable(oDesign, Para_Name, Para_value):
    oDesign.ChangeProperty(
        [
            "NAME:AllTabs",
            [
                "NAME:LocalVariableTab",
                [
                    "NAME:PropServers",
                    "LocalVariables"
                ],
                [
                    "NAME:ChangedProps",
                    [
                        "NAME:" + Para_Name,
                        "Value:=", Para_value
                    ]
                ]
            ]
        ]
    )

def change_object_material(oEditor, object_name, material_name):
    # 修改指定几何体的材料属性
    oEditor.ChangeProperty(
        [
            "NAME:AllTabs",
            [
                "NAME:Geometry3DAttributeTab",
                [
                    "NAME:PropServers",
                    object_name
                ],
                [
                    "NAME:ChangedProps",
                    [
                        "NAME:Material",
                        "Value:=", "\"" + material_name + "\""
                    ]
                ]
            ]
        ]
    )

class DotObject(object):
    def __init__(self, mapping):
        for key, value in mapping.items():
            setattr(self, key, self._convert(value))

    def _convert(self, value):
        if isinstance(value, dict):
            return DotObject(value)
        if isinstance(value, list):
            return [self._convert(item) for item in value]
        return value


# 导出HFSS报告为CSV文件的函数
def export_report_to_csv(oModule, Para, save_dir):
    # oModule: ReportSetup模块对象
    # Para: 报告名称字符串，如"S11mag"
    # save_dir: 保存目录（建议用绝对路径）
    oModule.UpdateReports([Para])
    oModule.ExportToFile(Para, os.path.join(save_dir, Para + ".csv"), False)

# end define function
################################################################################################################


# 导出HFSS网络数据为.tab文件的函数
def export_network_data(oDesign, filename, save_dir):
    # oDesign: HFSS Design对象
    # filename: 输出文件名（不含扩展名），如"sim_result_HFSSDesign1"
    # save_dir: 保存目录（建议用绝对路径）
    
    # 获取所有LocalVariables的属性名并构建VariationString
    property_names = oDesign.GetProperties('LocalVariableTab', 'LocalVariables')
    variation_parts = []
    for prop_name in property_names:
        prop_value = oDesign.GetPropertyValue('LocalVariableTab', 'LocalVariables', prop_name)
        # 格式: Name='Value'
        variation_parts.append("{0}='{1}'".format(prop_name, prop_value))
    
    # 用空格连接所有参数
    variation_string = " ".join(variation_parts)
    print("Variation String: {0}".format(variation_string))
    
    oModule = oDesign.GetModule("Solutions")
    output_path = os.path.join(save_dir, filename + ".tab")
    
    oModule.ExportNetworkData(
        variation_string,            # VariationString (自动构建)
        ["Setup1:Freq_Sweep"],       # SweepList
        2,                           # FileFormat (2 = Touchstone)
        output_path,                 # FilePath
        "all",                       # FreqUnits
        False,                       # Renormalize
        50,                          # ImpedanceVal
        ["S", "Zo", "Gamma"],        # DataType
        -1,                          # Pass
        0,                           # ComplexFormat
        15,                          # DigitsPrecision
        True,                        # UseScientificNotation
        True,                        # IncludeGammaComments
        False                        # IncludeMuComments
    )
    print("Network data exported to: {0}".format(output_path))

# ...existing code...

if __name__ == "__main__":
    # current_dir = os.path.dirname(os.path.abspath(__file__))
    ScriptEnv.Initialize("Ansoft.ElectronicsDesktop")
    oDesktop.RestoreWindow()
    # oProject = oDesktop.SetActiveProject("sim_result")
    oProject = oDesktop.GetActiveProject()
    objpath = oProject.GetPath()
    oDesign = oProject.SetActiveDesign("HFSSDesign1")
    
    # 导出报告为CSV
    oModule = oDesign.GetModule("ReportSetup")
    export_report_to_csv(oModule, "S21", objpath)
    export_report_to_csv(oModule, "S11", objpath)
    export_report_to_csv(oModule, "Nm", objpath)
    export_report_to_csv(oModule, "Terminal TDR Impedance Plot 1", objpath)
    export_report_to_csv(oModule, "a", objpath)
    export_report_to_csv(oModule, "GroupDelay", objpath)
    export_report_to_csv(oModule, "Zc_check", objpath)
    
    # 导出网络数据为.tab文件
    export_network_data(oDesign, "HFSS_matrix", objpath)

# oDesktop.QuitApplication()
