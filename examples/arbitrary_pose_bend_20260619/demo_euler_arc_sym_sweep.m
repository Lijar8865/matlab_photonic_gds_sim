clc;
clear;
close all;

%% Simple one-turn connection using Euler-Arc-Euler symmetry
% This demo is independent from the cubic single-bend and cubic S-bend.
theta_1 = deg2rad(15);
theta_2 = deg2rad(62);
pose_1 = [10, 15, theta_1];

% A symmetric one-turn bend requires the chord angle to be the mean port
% angle. Here x_2 is user-selected and y_2 follows from that condition.
x_2 = 60;
y_2 = pose_1(2)+(x_2-pose_1(1))*tan((theta_1+theta_2)/2);
pose_2 = [x_2, y_2, theta_2];

R_arc = 50;                           % circular-section radius (um)
R_max = 2000;                         % nearly straight Euler endpoints (um)
wg_width = 1.2;
etch_angle = 70;
wg_height = 0.25;
N_point = 501;

script_folder = fileparts(mfilename('fullpath'));
repo_root = fileparts(fileparts(script_folder));
addpath(fullfile(repo_root, 'lib'));

total_angle = mod(theta_2-theta_1+pi,2*pi)-pi;
assert(total_angle > 0, 'This simple demo currently uses a positive bend angle.');
target_chord = hypot(pose_2(1)-pose_1(1),pose_2(2)-pose_1(2));
target_chord_angle = atan2(pose_2(2)-pose_1(2),pose_2(1)-pose_1(1));
symmetry_error = abs(mod(target_chord_angle-(theta_1+total_angle/2)+pi,2*pi)-pi);
assert(symmetry_error < 1e-10, ...
    'Symmetric bend requires chord angle = (theta_1+theta_2)/2.');

make_bend = @(arc_angle,n) Wcli_wg.euler_arc_sym_bend_gen( ...
    'R_max',R_max,'R_arc',R_arc,'total_angle',total_angle, ...
    'arc_angle',arc_angle,'N_point',n,'W_inout',wg_width, ...
    'W_mid',wg_width,'etch_angle',etch_angle,'h_wg',wg_height, ...
    'initial_angle',theta_1);

%% Coarse arc_angle traversal
arc_angle_list = linspace(deg2rad(0.2),total_angle-deg2rad(0.2),25);
chord_mismatch = zeros(size(arc_angle_list));
for i = 1:numel(arc_angle_list)
    candidate = make_bend(arc_angle_list(i),101);
    candidate_chord = hypot(candidate.WTX(end)-candidate.WTX(1), ...
        candidate.WTY(end)-candidate.WTY(1));
    chord_mismatch(i) = candidate_chord-target_chord;
end

crossing = find(chord_mismatch(1:end-1).*chord_mismatch(2:end) <= 0,1);
if isempty(crossing)
    best_error = min(abs(chord_mismatch));
    error(['arc_angle sweep did not bracket the requested endpoint. ', ...
        'Best chord error is %.3f um. Change R_arc/R_max or the target pose.'],best_error);
end

% Refine only inside the bracket found by traversal.
arc_angle_opt = fzero(@(a) arc_chord_mismatch(a,make_bend,target_chord), ...
    arc_angle_list([crossing,crossing+1]),optimset('TolX',1e-11));
euler_arc_bend = make_bend(arc_angle_opt,N_point);
euler_arc_bend.transform_shape(0,pose_1(1),pose_1(2));

position_error = hypot(euler_arc_bend.WTX(end)-pose_2(1), ...
    euler_arc_bend.WTY(end)-pose_2(2));
angle_error = abs(mod(euler_arc_bend.theta_list(end)-theta_2+pi,2*pi)-pi);
assert(position_error < 1e-5);
assert(angle_error < 1e-9);

fprintf('Euler-Arc symmetric sweep verification passed.\n');
fprintf('  optimized arc_angle = %.6f deg\n',rad2deg(arc_angle_opt));
fprintf('  position error      = %.3e um\n',position_error);
fprintf('  angle error         = %.3e rad\n',angle_error);
fprintf('  R_arc               = %.3f um\n',R_arc);

%% Shape, curvature, and sweep plots
fig_shape = figure('Color','w','Name','Euler-Arc symmetric bend');
euler_arc_bend.plot_2d('face_color','#0891b2','edge_color','#155e75', ...
    'face_alpha',0.8,'edge_width',0.8);
hold on;
plot(euler_arc_bend.WTX,euler_arc_bend.WTY,'k--','LineWidth',0.8);
axis equal; grid on;
xlabel('x (um)'); ylabel('y (um)');
title(sprintf('Euler-Arc-Euler symmetric bend, arc angle = %.3f deg', ...
    rad2deg(arc_angle_opt)));
exportgraphics(fig_shape,fullfile(script_folder, ...
    'demo_euler_arc_sym_sweep.png'),'Resolution',180);

fig_kappa = figure('Color','w','Name','Euler-Arc symmetric curvature');
euler_arc_bend.plot_kappa_all(fig_kappa);
hold on;
yline(1/R_arc,'r--','LineWidth',1.2,'Label','1/R_{arc}');
grid on;
exportgraphics(fig_kappa,fullfile(script_folder, ...
    'demo_euler_arc_sym_sweep_kappa.png'),'Resolution',180);

fig_sweep = figure('Color','w','Name','arc angle traversal');
plot(rad2deg(arc_angle_list),chord_mismatch,'o-','LineWidth',1.1);
hold on;
xline(rad2deg(arc_angle_opt),'r--','LineWidth',1.2,'Label','solution');
yline(0,'k:'); grid on;
xlabel('arc angle (deg)'); ylabel('chord length error (um)');
title('arc\_angle traversal and bracketed solution');
exportgraphics(fig_sweep,fullfile(script_folder, ...
    'demo_euler_arc_sym_sweep_search.png'),'Resolution',180);

%% Nested objective: signed chord mismatch
function mismatch = arc_chord_mismatch(arc_angle,make_bend,target_chord)
    bend = make_bend(arc_angle,151);
    bend_chord = hypot(bend.WTX(end)-bend.WTX(1), ...
        bend.WTY(end)-bend.WTY(1));
    mismatch = bend_chord-target_chord;
end
