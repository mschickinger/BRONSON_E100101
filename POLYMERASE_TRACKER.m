% Adaptations from TWO_COLOR_TRACKER_v12c (hpcluster):

% Average images are stored differently (different cell structure)

% Spot finding for Polymerase channel performed throughout whole movie (in
% blocks of size N_frames)

%% startup
cd(matlab_dir)
clc, clear all, close all
run my_prefs.m


%% choose colors
rgb={'red','green','blue'};
[colors,ok]=listdlg('PromptString', 'Select two colors to be analyzed',...
                'ListString', rgb,...
                'OKString', 'Engage');
while ne(length(colors),2) && ok>0
    [colors,ok]=listdlg('PromptString', 'Select _TWO_ colors to be analyzed',...
                'ListString', rgb,...
                'OKString', 'Engage');
end

channel = cell(2,1);
channel{1} = rgb{colors(1)};
channel{2} = rgb{colors(2)};

[chb,ok]=listdlg('PromptString', 'Which one is surface-bound?',...
                'ListString', channel, 'SelectionMode', 'single',...
                'OKString', 'Confirm');           
chm = (chb == 1) + 1;

%% LOAD STACK OF MOVIES
pname=uigetdir(data_dir,'Choose the folder with all .fits files.');
files_ch1 = pickFirstFitsFiles(pname, channel{1}); 
files_ch2 = pickFirstFitsFiles(pname, channel{2});

N_movie = length(files_ch1);
if length(files_ch1) ~= length(files_ch2)
    disp('WARNING: not same number of movie files!')
end

path_out = [pname filesep datestr(now, 'yyyy-mm-dd_HH-MM') '_analysis'];
mkdir(path_out)

%% SET PARAMETER
button = questdlg('Assign parameters individually for each movie?');
options.Resize = 'on';
input = {'First Frame:', 'Last Frame (-1=all):', ['Sequence ' channel{1} ':'], ['Sequence ' channel{2} ':'],... % sample options
    'Radius of peak [pixel]:', 'Integration radius [pixel]:', 'Time per frame (in ms):',...
    'Average over first N_frames:'};
input_default = {'2', '-1', '1', '1', '4', '3', '50', '500'};

if button(1) == 'N'
tmp = inputdlg(input, 'All movies', 1, input_default, options);
end

first = ones(N_movie,1).*str2double(input_default{1});
last = ones(N_movie,1).*str2double(input_default{2});
time_per_frame = ones(N_movie,1).*str2double(input_default{7});
sequences = cell(N_movie,size(channel,1));
for m = 1:N_movie
    if button(1) == 'Y'
        tmp = inputdlg(input, ['Movie #' num2str(m)], 1, input_default, options);
    end
    first(m) = round(str2double(tmp(1))); % first image to read from file
    last(m) = round(str2double(tmp(2))); % last image to read from file
    time_per_frame(m) = str2double(tmp(7)); % time per frame used during acquisition
    %determine sequences
    for ch = 1:size(sequences,2)
    sequences{m,ch} = zeros(1, size(tmp{2+ch},2));
        for i=1:size(tmp{2+ch},2)
            if(tmp{2+ch}(i) == '1')
                sequences{m,ch}(1,i) = 1;
            end
        end
    end
end

r_find = str2double(tmp(5)); % radius used to find spots
r_integrate = str2double(tmp(6)); % radius used for integration of intensities
N_frames = str2double(tmp(8)); % number of frames that is used for average

%% generate movie classes
ch1 = cell(N_movie,1);
ch2 = cell(N_movie,1);

for i=1:N_movie
    ch1{i} = movie(pname, files_ch1{i}, first(i), last(i), sequences{i,1}); % pname, fname, first, last, sequence
    ch2{i} = movie(pname, files_ch2{i}, first(i), last(i), sequences{i,2}); % pname, fname, first, last, sequence
end
movies = [ch1 ch2];
%%
button = questdlg(['Map positions ' channel{1} ' ON ' channel{2} ' and vice versa?'],'Mapping','Yes','No','No');
mapping = strcmp(button, 'Yes');

button = questdlg('Perform drift correction?','Drift correction','Yes','No','Yes');
drift_cor = strcmp(button, 'Yes');
%%
if mapping
    [mapping_file_1TO2, mapping_dir]=uigetfile(data_dir,['Choose the ' channel{1} '2' channel{2} ' mapping file:']);
    map1TO2 =load([mapping_dir mapping_file_1TO2], 'tform');
    tform_1TO2 = map1TO2.tform;
    display(['loaded ' channel{1} ' TO ' channel{2} ' mapping file: ' mapping_dir mapping_file_1TO2]);
    
    [mapping_file_2TO1]=uigetfile(mapping_dir,['Choose the ' channel{2} '2' channel{1} ' mapping file:']);
    map2TO1=load([mapping_dir mapping_file_2TO1]);
    tform_2TO1 = map2TO1.tform; %['tform_' channel{2} 'ON' channel{1}];
    display(['loaded ' channel{2} ' TO ' channel{1} ' mapping file: ' mapping_dir mapping_file_2TO1]);
    
    tform = {tform_2TO1, tform_1TO2};
else
    tform = cell(2,1);
end

%% compute average images
avg_img = cell(N_movie, 2);
for m = 1:N_movie    
    avg_img{m,chb} = {movies{m,chb}.average_image(N_frames);...
                        movies{m,chb}.average_image_last(N_frames)};
    avg_img{m,chm} = cell(ceil(length(movies{m,chm}.frames)./N_frames),1);
    for j = 1:size(avg_img{m,chm},1)
    avg_img{m,chm}{j} = movies{m,chm}.average_image_from((j-1)*N_frames+1, N_frames);
    end
end

%% get threshold and find peaks from first N_frames (bound channel) and all N_frames-long intervals (Polymerase channel)

peaks_raw = zeros(0,5);
peaks_found = cell(N_movie,2);

if mapping
pos1on2 = cell(N_movie, 1);
pos2on1 = cell(N_movie, 1);
end

for m=1:N_movie 
    [threshold, pos_chb] = movies{m,chb}.get_threshold(r_find, avg_img{m,chb}{1});
    peaks_found(m,chb) = pos_chb;
    pos_chm = [];
    peaks_found{m,chm} = cell(size(avg_img{m,chm}));
    for j = 1:size(avg_img{m,chm},1)
    [threshold, tmp] = movies{m,chm}.get_threshold(r_find, avg_img{m,chm}{j});
    pos_chm = [pos_chm; tmp];
    peaks_found{m,chm}{j} = tmp;
    end
    
    if chb == 1
        pos_ch1 = pos_chb;
        pos_ch2 = pos_chm;
    else
        pos_ch1 = pos_chm;
        pos_ch2 = pos_chb;
    end

    if mapping
        pos1on2{m} = transformPointsInverse(tform_2TO1, pos_ch1(:,1:2));  %%this takes coords in ch1 and transforms them to coords in ch2
        pos2on1{m} = transformPointsInverse(tform_1TO2, pos_ch2(:,1:2));  %%this takes coords in ch2 and transforms them to coords in ch1
    end
    
    % map peaks
    trace_map = map_traces(pos_ch1(:,1:2), pos_ch2(:,1:2), pos_ch2(:,1:2), r_find*2)+1; %map the traces from average positions
    tmp = zeros(size(trace_map,1),5);
   
    % combine pairs
    for j=1:size(trace_map,1)
        tmp(j,:) = [pos_ch1(trace_map(j,1), 1:2)+1 pos_ch2(trace_map(j,2), 1:2)+1 m]; %x_1 y_1 x_2 y_2 frame
    end
    
    peaks_raw = [peaks_raw; tmp];
end

N_peaks_raw = size(peaks_raw,1);
display(['You have ' num2str(N_peaks_raw) ' pairs'])

%% drift correction
if drift_cor
    
    interval = 100;
    p = 129;
    q = 384;
    drift_cor = cell(N_movie,1);
    
    display('Calculating drift displacements.. please wait');
    % Go by intervals
    for m=1:N_movie
        drift_cor{m} = zeros(ceil(length(movies{m,ch}.frames)/interval),2);
        for i = 1:size(drift_cor{m},1)
        ai = zeros(512,512);
        for j = 1:min([interval length(movies{m,chb}.frames)-(i-1)*interval])
            ai = ai + movies{m,ch}.readFrame(movies{m,ch}.frames((i-1)*interval+j));
        end
        ai = ai./interval;
        tmp = normxcorr2(ai(p:q,p:q), avg_img{m,chb}{1}(p:q,p:q));
        [v, ind] = max(tmp(:));
        [a, b] = ind2sub(size(tmp),ind);
        drift_cor{m}(i,1) = 256-b;
        drift_cor{m}(i,2) = 256-a;
        end
    end
    % Show drift paths
    for m = 1:N_movie
    close all
    figure('Position', [scrsz(1) scrsz(4)/4 scrsz(3) scrsz(4)/2])
    subplot(1,3,1)
    hold off 
    plot(drift_cor{m}(:,1),drift_cor{m}(:,2), 'k-')
    hold on
    plot(drift_cor{m}(:,1),drift_cor{m}(:,2), 'k.', 'MarkerSize', 8)
    xlim([min(drift_cor{m}(:,1))-1 max(drift_cor{m}(:,1))+1])
    ylim([min(drift_cor{m}(:,2))-1 max(drift_cor{m}(:,2))+1])
    axis equal
    title(['Drift path for movie #' num2str(m)])
    subplot(1,3,2)
    imagesc(avg_img{m,chb}{1}), axis image, colormap gray, title(['First ' num2str(N_frames) ' frames'])
    subplot(1,3,3)
    imagesc(avg_img{m,chb}{2}), axis image, colormap gray, title(['Last ' num2str(N_frames) ' frames'])
    pause
    end
    
    % Write drift array
    for m = 1:N_movie
    ch1{m}.drift = zeros(length(ch1{m}.frames),2);
    for i = 1:length(ch1{m}.frames)
        ch1{m}.drift(i,:) = drift_cor{m}(ceil(i/interval),:);
    end
    ch2{m}.drift = zeros(length(ch2{m}.frames),2);
    for i = 1:length(ch2{m}.frames)
        ch2{m}.drift(i,:) = drift_cor{m}(ceil(i/interval),:);
    end
end
end

%% Fit psf to spots
s_x = 2.5;
s_y = 2.5;
w_fit = 8;

chb_fit_raw = zeros(N_peaks_raw, 7); 
chb_fit_err_raw = zeros(N_peaks_raw, 7);
chm_fit_raw = zeros(N_peaks_raw, 7); 
chm_fit_err_raw = zeros(N_peaks_raw, 7);
h = waitbar(0,'Fitting spots.. please wait');

for i=1:N_peaks_raw 
    
    % bound channel
    xb = round(peaks_raw(i,2*chb-1));
    yb = round(peaks_raw(i,2*chb));
    [c, c_err, ci, area] = fit_gauss2d_mainaxis_bg(xb, yb, s_x, w_fit, avg_img{peaks_raw(i, 5),chb}{1});
    chb_fit_raw(i,:) = c;
    chb_fit_err_raw(i,:) = c_err;
%{
    % unbound channel
    xm = round(peaks_raw(i,3));
    ym = round(peaks_raw(i,4));
    [c, c_err, ci, area] = fit_gauss2d_mainaxis_bg(xm, ym, s_x, w_fit, avg_img{peaks_raw(i, 5),chm}{1});
    chm_fit_raw(i,:) = c;
    chm_fit_err_raw(i,:) = c_err;
%}    
    waitbar( i/N_peaks_raw , h, ['Fitting spot... ' num2str(i) ' of ' num2str(N_peaks_raw) ' done']) % update waitbar

end

close(h)

%% SORT OUT: remove spots where ratio of width is not close to 1 and which are too large

criteria = ones(N_peaks_raw,2);
criteria(:,1:2) = filter_spots(chb_fit_raw(:,3:4), [0.9 10/9], [2 2]);
accepted = [criteria(:,1) & criteria(:,2)];

%remove not-accepted spots

peaks = peaks_raw(accepted==1, :);

plot_discarded = strcmp(questdlg('Plot discarded spots?','Plot discarded','Yes','No','No'), 'Yes');
if plot_discarded
    path_out_discarded = [path_out filesep 'discarded'];
    mkdir(path_out_discarded)
end

plot_accepted = strcmp(questdlg('Plot accepted spots?','Plot accepted','Yes','No','No'), 'Yes');
if plot_accepted
    path_out_accepted= [path_out filesep 'accepted'];
    mkdir(path_out_accepted)
end

close all
fig_dim =1*[20 10];
cur_fig = figure('Visible','off', 'PaperPositionMode', 'manual','PaperUnits','centimeters','PaperPosition', [0 0 fig_dim(1) fig_dim(2)], 'Position', [0 scrsz(4) fig_dim(1)*40 fig_dim(2)*40]);
colormap gray
w_plot = 10;


if plot_discarded
    display('Plotting discarded spots...')
    for i=1:N_peaks_raw
        if ~accepted(i) % discarded spot
            message = {['Sigma ratio ' channel{chb} ' OK: ' num2str(chb_fit_raw(i,3)./chb_fit_raw(i,4))],...
                ['Spotsize ' channel{chb} ' OK: ' num2str(sqrt(chb_fit_raw(i,3).^2+chb_fit_raw(i,4).^2))]};
            if criteria(i,1)==0
                message{1} = ['Sigma ratio ' channel{chb} ' BAD: ' num2str(chb_fit_raw(i,3)./chb_fit_raw(i,4))];
            end
            if criteria(i,2)==0
                message{2} = ['Spotsize ' channel{chb} 'BAD: ' num2str(sqrt(chb_fit_raw(i,3).^2+chb_fit_raw(i,4).^2))];
            end
           
            x_1 = chb_fit_raw(i,1);
            y_1 = chb_fit_raw(i,2);

            plot_subframe(avg_img{peaks_raw(i, 5),chb}{1}, x_1, y_1, w_plot), hold on
            plot(x_1, y_1, [channel{chb}(1) '.'])
            ellipse(chb_fit_raw(i,3), chb_fit_raw(i,4), -chb_fit_raw(i,5), x_1, y_1, channel{chb});
            title({['Pair ' num2str(i) ' of '  num2str(N_peaks_raw) ' at (' num2str(round(x_1)) ',' num2str(round(y_1)) ') in ' channel{chb} ' channel'], message{1},message{2}})
            axis square
            hold off

            print(cur_fig, '-dtiff', '-r150',  [path_out_discarded filesep 'Discarded_' num2str(i) '.tif'])
        end 
    end
end

if plot_accepted
    display('Plotting accepted spots...')
    for i=1:N_peaks_raw
        if  accepted(i) % accepted spot
            message = {['Sigma ratio ' channel{chb} ' OK: ' num2str(chb_fit_raw(i,3)./chb_fit_raw(i,4))],...
                ['Spotsize ' channel{chb} ' OK: ' num2str(sqrt(chb_fit_raw(i,3).^2+chb_fit_raw(i,4).^2))]};
           
            x_1 = chb_fit_raw(i,1);
            y_1 = chb_fit_raw(i,2);

            plot_subframe(avg_img{peaks_raw(i, 5),chb}{1}, x_1, y_1, w_plot), hold on
            plot(x_1, y_1, [channel{chb}(1) '.'])
            ellipse(chb_fit_raw(i,3), chb_fit_raw(i,4), -chb_fit_raw(i,5), x_1, y_1, channel{chb});
            title({['Pair ' num2str(i) ' of '  num2str(N_peaks_raw) ' at (' num2str(round(x_1)) ',' num2str(round(y_1)) ') in ' channel{chb} ' channel'], message{1},message{2}})
            axis square
            hold off

            print(cur_fig, '-dtiff', '-r150',  [path_out_accepted filesep 'Accepted_' num2str(i) '.tif'])
        end 
    end
end

display(['Accepted ' num2str(sum(accepted)) ' spots.'])
display(['Discarded ' num2str(sum(~accepted)) ' spots.'])
close all
N_peaks = size(peaks,1);

%% Get intensity traces 'itraces' plus median filtered itraces
display('Getting intensity traces... please wait')
tic
merged_itraces = cell(N_movie,5);
iEndval = cell(N_movie,2);
iEndval_sorted = cell(N_movie,2);
avg_iEndval = zeros(N_movie,2);
avg_iEndval_tenth = zeros(N_movie,2);
for i=1:N_movie 
    %get fluorescence intensity traces from position    
    ch1_itraces_full = ch1{i}.int_spots_in_frames(1:length(ch1{i}.frames), peaks(peaks(:,5)==i,1:2), r_integrate);
    display(['Tracing ' channel{1} ' channel in movie #' num2str(i) ' done'])
    toc %
    ch2_itraces_full = ch2{i}.int_spots_in_frames(1:length(ch2{i}.frames), peaks(peaks(:,5)==i,3:4), r_integrate);
    display(['Tracing ' channel{2} ' channel in movie #' num2str(i) ' done'])
    toc %
    movnumber = cell(size(ch1_itraces_full));
    movnumber(:) = {i};
    merged_itraces{i,1} = ch1_itraces_full;
    merged_itraces{i,2} = ch2_itraces_full;
    merged_itraces{i,3} = movnumber;
    
    %add median filtered itraces and average intensity values (over 100 frames) at the end
    tmp = cell(length(ch1_itraces_full),2);
    iEndval{i,1} = zeros(size(ch1_itraces_full,1),1);
    iEndval{i,2} = zeros(size(ch2_itraces_full,1),1);
    for j=1:length(ch1_itraces_full)
    tmp{j,1} = medfilt1(ch1_itraces_full{j}(:,4),20);
    tmp{j,2} = medfilt1(ch2_itraces_full{j}(:,4),20);
    iEndval{i,1}(j) = mean(ch1_itraces_full{j}(end-100:end,4));
    iEndval{i,2}(j) = mean(ch2_itraces_full{j}(end-100:end,4));
    end
    merged_itraces{i,4} = tmp;
    for ch = 1:2
    avg_iEndval(i,ch) = mean(iEndval{i,ch});
    [tmp_val, tmp_spot] = sort(iEndval{i,ch});
    iEndval_sorted{i,ch} = [tmp_spot, tmp_val];
    avg_iEndval_tenth(i,ch) = mean(iEndval_sorted{i,ch}(1:ceil(length(iEndval_sorted{i,ch})/10),2));
    end
end
display('itraces complete')
toc %
%% Determine fitting parameters
fit_cutoff = cell(N_movie,2);

fc = figure('Position', scrsz);

for m = 1:N_movie
    for ch = 1:2
    if size(merged_itraces{m,ch},1) > 0
        fit_cutoff{m,ch} = zeros(size(merged_itraces{m,ch},1),1);
    def_fc = iEndval_sorted{m,ch}(1,2);
    for j = 1:size(merged_itraces{m,ch},1) %cycle through spots, in iEndval ascending order
        
        
        act_spotnum = iEndval_sorted{m,ch}(j,1);
        x_0 = round(merged_itraces{m,ch}{act_spotnum}(1,2));
        y_0 = round(merged_itraces{m,ch}{act_spotnum}(1,3));
        x_0_end = round(merged_itraces{m,ch}{act_spotnum}(end,2));
        y_0_end = round(merged_itraces{m,ch}{act_spotnum}(end,3));
        
        subplot('Position', [0.05,0.55,0.65,0.4])
        hold off
        plot (1:size(iEndval_sorted{m,ch},1),iEndval_sorted{m,ch}(:,2), [channel{ch} '.'], 'MarkerSize', 3);
        hold on
        plot (j,iEndval_sorted{m,ch}(j,2), 'ko', 'MarkerSize', 4);
        plot (1:length(iEndval_sorted{m,ch}),ones(1,length(iEndval_sorted{m,ch}))*1.5*avg_iEndval_tenth(m,ch), '-b');
        plot (1:length(iEndval_sorted{m,ch}),ones(1,length(iEndval_sorted{m,ch}))*1.5*avg_iEndval(m,ch), '-k');
        title('Average end value distribution (ascending order)')
        
        subplot('Position', [0.05,0.05,0.65,0.4])
        hold off
        plot(merged_itraces{m,ch}{act_spotnum}(:,1), ...
            merged_itraces{m,ch}{act_spotnum}(:,4),...
            ['-' channel{ch}(1)], 'LineWidth', 0.5)
        hold on
        plot(merged_itraces{m,ch}{act_spotnum}(:,1), ...
            merged_itraces{m,4}{act_spotnum,ch},...
            '-k', 'LineWidth', 0.25)
        plot(merged_itraces{m,ch}{act_spotnum}(:,1), ones(1,size(merged_itraces{m,ch}{act_spotnum},1)).*def_fc, ...
            'color', [1 1 1].*0.7, 'LineStyle', '-.')
        tmp = ylim;
        set(gca, 'YTick', tmp(1):500:tmp(2), 'Layer', 'top')
        grid on
        xlim([merged_itraces{m,ch}{act_spotnum}(1,1) merged_itraces{m,ch}{act_spotnum}(end,1)])
        title('Intensity trace')
        
        subplot('Position', [0.75,0.55,0.25,0.4])
        hold off
        plot_subframe(avg_img{m,ch}{1}, x_0, y_0, 6)
        hold on
        ellipse(r_integrate, r_integrate, 0, x_0, y_0, channel{ch})
        title(['Averaged over first ' num2str(N_frames) ' frames']);
        axis square
        set(gca, 'YDir', 'normal')
        
        subplot('Position', [0.75,0.05,0.25,0.4])
        hold off
        plot_subframe(avg_img{m,ch}{end}, x_0_end, y_0_end, 6)
        hold on
        ellipse(r_integrate, r_integrate, 0, x_0_end, y_0_end, channel{ch})
        title(['Averaged over last ' num2str(N_frames) ' frames']);
        axis square
        set(gca, 'YDir', 'normal')
        
        tmp = inputdlg(['Cutoff intensity for movie #' num2str(m) ', ' channel{ch} ' channel, spot #' ...
            num2str(act_spotnum)], 'Cutoff intensity', 1, {num2str(def_fc)});
        if isempty(tmp)
            break
        end
        fit_cutoff{m,ch}(act_spotnum) = str2double(tmp);
        def_fc = (str2double(tmp)>0)*str2double(tmp);
        end
    end
    end
end

close all
%%
%pos_in_frame: cell of arrays that for each frame gives starting fit
%coordinates for all spots in respective channel. If both parameters
%return zero, spot is not fitted in that frame.

pos_in_frame = cell(N_movie,2);
for m = 1:N_movie
    % channel 1
    pos_in_frame{m,1} = cell(size(ch1{m}.frames,2),1);
    for j = 1:size(pos_in_frame{m,1},1)
        pos_in_frame{m,1}{j} = zeros(size(merged_itraces{m,1},1),2);
        for s=1:size(pos_in_frame{m,1}{j},1)
        pos_in_frame{m,1}{j}(s,1:2) = (merged_itraces{m,4}{s,1}(j)>=fit_cutoff{m,1}(s))*(merged_itraces{m,1}{s}(j,2:3)); % x_0, y_0 remain zero if intensity is below threshold
        end
    end

    % channel 2
    pos_in_frame{m,2} = cell(size(ch2{m}.frames,2),1);
    for j = 1:size(pos_in_frame{m,2},1)
        pos_in_frame{m,2}{j} = zeros(size(merged_itraces{m,2},1),2);
        for s=1:size(pos_in_frame{m,2}{j},1)
        pos_in_frame{m,2}{j}(s,1:2) = (merged_itraces{m,4}{s,2}(j)>=fit_cutoff{m,2}(s))*(merged_itraces{m,2}{s}(j,2:3)); % x_0, y_0 remain zero if intensity is below threshold
        end
    end
end

%% Save all relevant data; prepare for batch job assignment
data = cell(N_movie,1);
cd(path_out)
for m=1:N_movie %loop through movies
    data{m} = cell(size(merged_itraces{m,1},1),2);
        for s=1:size(data{m},1)
            for ch = 1:2
                data{m}{s,ch}.pos0 = merged_itraces{m,ch}{s}(:,2:3);
                data{m}{s,ch}.itrace = merged_itraces{m,ch}{s}(:,4);
                data{m}{s,ch}.med_itrace = merged_itraces{m,4}{s,ch}(:);
            end
        end
end
% file that the position data from gF and vwcm estimators will be added to
save -v7.3 'data_spot_pairs.mat' 'data' 'path_out'

% data needed for processing (batch jobs and later)
if mapping
save -v7.3 'data_proc.mat' 'pos_in_frame' 'time_per_frame' 'tform' 'mapping'
else
save -v7.3 'data_proc.mat' 'pos_in_frame' 'time_per_frame' 'tform' 'mapping'    
end

% movie objects
save -v7.3 'movie_objects.mat' 'ch1' 'ch2'

% stuff that might be useful for plotting figures
save 'data_plot.mat' 'channel' 'fit_cutoff' 'chb' 'chm'

% for archiving purposes
save -v7.3 'data_archive.mat' 'avg_img' 'N_frames' 'r_find' 'r_integrate' 'peaks_found' 'peaks_raw' 'peaks' 'pos1on2' 'pos2on1'

%% start position estimator batch job
pos_v1(path_out);
%{
mycluster=parcluster('local');
pos_job = batch(mycluster, @par_pos_v1, 1, {path_out} ...
    ,'CaptureDiary',true, 'CurrentDirectory', '.', 'Pool', 2 ...
    ,'AdditionalPaths', {[matlab_dir filesep 'TOOLBOX_GENERAL'], [matlab_dir filesep 'TOOLBOX_MOVIE'],...
    [matlab_dir filesep 'FM_applications'], [matlab_dir filesep 'DEVELOPMENT']});
%}
disp('Done')
% End of program
