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

# 定义创建报告的函数
def create_report(oDesign,report_name, y_components, setup_name="Setup1 : Freq_Sweep"):
    # """
    # 创建HFSS报告
    
    # 参数:
    #     report_name: 报告名称
    #     y_components: Y轴变量列表，例如 ["beta_S", "im(beta_ab)"]
    #     setup_name: 求解设置名称，默认 "Setup1 : Freq_Sweep"
    # """
    oModule = oDesign.GetModule("ReportSetup")
    
    # 如果 y_components 是字符串，转换为列表
    if isinstance(y_components, str):
        y_components = [y_components]
    
    oModule.CreateReport(report_name, "Terminal Solution Data", "Rectangular Plot", setup_name, 
        [
            "Domain:="		, "Sweep"
        ], 
        [
            "Freq:="		, ["All"],
            "W:="			, ["Nominal"],
            "H_box:="		, ["Nominal"],
            "H_slab:="		, ["Nominal"],
            "H_sub:="		, ["Nominal"],
            "W_S:="			, ["Nominal"],
            "G:="			, ["Nominal"],
            "W_WG:="		, ["Nominal"],
            "H_etch:="		, ["Nominal"],
            "H_clad:="		, ["Nominal"],
            "theta_etch:="	, ["Nominal"],
            "W_G:="			, ["Nominal"],
            "H_Au:="		, ["Nominal"],
            "L_lump:="		, ["Nominal"],
            "period:="		, ["Nominal"],
            "W_T:="			, ["Nominal"],
            "L_T:="			, ["Nominal"],
            "W_rail:="		, ["Nominal"],
            "L_rail:="		, ["Nominal"],
            "Gap:="			, ["Nominal"],
            "N_ele:="		, ["Nominal"],
            "H_up_cald:="	, ["Nominal"]
        ], 
        [
            "X Component:="	, "Freq",
            "Y Component:="	, y_components
        ])


# 导出HFSS报告为CSV文件的函数
def export_report_to_csv(oModule, Para, save_dir):
    # oModule: ReportSetup模块对象
    # Para: 报告名称字符串，如"S11mag"
    # save_dir: 保存目录（建议用绝对路径）
    oModule.UpdateReports([Para])
    oModule.ExportToFile(Para, os.path.join(save_dir, Para + ".csv"), False)

# end define function
################################################################################################################


if __name__ == "__main__":
    # current_dir = os.path.dirname(os.path.abspath(__file__))
    ScriptEnv.Initialize("Ansoft.ElectronicsDesktop")
    oDesktop.RestoreWindow()
    oProject = oDesktop.GetActiveProject()
    oDesign = oProject.SetActiveDesign("HFSSDesign1")
#创建新的输出变量
    oModule = oDesign.GetModule("OutputVariable")
    oModule.CreateOutputVariable("A_m", "((1 + St(S1_T1,S1_T1))*(1 - St(S2_T1,S2_T1)) + St(S1_T1,S2_T1)*St(S2_T1,S1_T1)) / (2*St(S2_T1,S1_T1))", "Setup1 : Freq_Sweep", "Terminal Solution Data", [])
    oModule.CreateOutputVariable("B_m", "Zot(S1_T1,S1_T1)*((1 + St(S1_T1,S1_T1))*(1 + St(S2_T1,S2_T1)) - St(S1_T1,S2_T1)*St(S2_T1,S1_T1)) / (2*St(S2_T1,S1_T1))", "Setup1 : Freq_Sweep", "Terminal Solution Data", [])
    oModule.CreateOutputVariable("C_m", "(1/Zot(S1_T1,S1_T1)) * ((1 - St(S1_T1,S1_T1))*(1 - St(S2_T1,S2_T1)) - St(S1_T1,S2_T1)*St(S2_T1,S1_T1)) / (2*St(S2_T1,S1_T1))", "Setup1 : Freq_Sweep", "Terminal Solution Data", [])
    oModule.CreateOutputVariable("D_m", "((1 - St(S1_T1,S1_T1))*(1 + St(S2_T1,S2_T1)) + St(S1_T1,S2_T1)*St(S2_T1,S1_T1)) / (2*St(S2_T1,S1_T1))", "Setup1 : Freq_Sweep", "Terminal Solution Data", [])
    oModule.CreateOutputVariable("Z_m", "sqrt(B_m/C_m)", "Setup1 : Freq_Sweep", "Terminal Solution Data", [])
    oModule.CreateOutputVariable("beta_S", "-cang_rad(St(S2_T1,S1_T1))/Li", "Setup1 : Freq_Sweep", "Terminal Solution Data", [])
    oModule.CreateOutputVariable("beta_ab", "acosh(A_m)/Li", "Setup1 : Freq_Sweep", "Terminal Solution Data", [])
    oModule.CreateOutputVariable("beta_bc", "asinh((B_m*C_m)^0.5)/Li", "Setup1 : Freq_Sweep", "Terminal Solution Data", [])
    oModule.CreateOutputVariable("VSWR_cmp", "(1+St(S1_T1,S1_T1))/(1-St(S1_T1,S1_T1))", "Setup1 : Freq_Sweep", "Terminal Solution Data", [])
    # oModule.CreateOutputVariable("tanhbetaL", "sqrt(B_m*C_m/(A_m*D_m))", "Setup1 : Freq_Sweep", "Terminal Solution Data", [])
    # oModule.CreateOutputVariable("Zcc", "50*(cmplx(0, 1)*VSWR_cmp*tan(-cang_rad(St(S2_T1,S1_T1)))-1)/(cmplx(0, 1)*tan(-cang_rad(St(S2_T1,S1_T1)))-VSWR_cmp)", "Setup1 : Freq_Sweep", "Terminal Solution Data", [])
    # oModule.CreateOutputVariable("Zcc", "50*(VSWR_cmp*tanhbetaL-1)/(tanhbetaL-VSWR_cmp)", "Setup1 : Freq_Sweep", "Terminal Solution Data", [])
#获取路径
    objpath = oProject.GetPath()

    create_report(oDesign,"beta_check", ["beta_S", "im(beta_ab)", "im(beta_bc)"])
    create_report(oDesign,"Zc_check", ["mag(Z_m)", "mag(Zcc)"])
#导出csv
    # oModule = oDesign.GetModule("ReportSetup")
    # export_report_to_csv(oModule, "beta_check", objpath)
    # export_report_to_csv(oModule, "Zc_check", objpath)
# oDesktop.QuitApplication()
